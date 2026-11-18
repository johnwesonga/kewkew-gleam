import client/router
import client/visitor_queue
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import plinth/browser/crypto as browser_crypto
import plinth/browser/web_storage
import plinth/browser/window
import rsvp

pub opaque type Model {
  Model(
    public_queue: Option(PublicQueueDetails),
    public_location: Option(PublicLocationData),
    join_attempt_token: String,
    join_pending: Bool,
    join_error: Option(String),
    tracked_ticket: Option(TrackedTicket),
  )
}

pub type PublicQueueDetails {
  PublicQueueDetails(
    organization: String,
    location_id: String,
    location: String,
    service: String,
    queue: String,
    availability: visitor_queue.Availability,
    scheduled_service_start_at: Option(String),
  )
}

pub type PublicLocationData {
  PublicLocationData(
    organization: String,
    location: String,
    services: List(PublicServiceChoice),
  )
}

pub type PublicServiceChoice {
  PublicServiceChoice(
    name: String,
    queue_name: String,
    public_id: String,
    availability: visitor_queue.Availability,
    waiting_count: Int,
  )
}

pub type JoinResponse {
  JoinResponse(tracking_token: String)
}

pub type TrackedTicket {
  TrackedTicket(
    ticket_number: Int,
    status: String,
    queue_position: Option(Int),
    queue: String,
    service: String,
    location: String,
  )
}

pub type Message {
  PublicQueueLoaded(Result(PublicQueueDetails, rsvp.Error(String)))
  PublicLocationLoaded(Result(PublicLocationData, rsvp.Error(String)))
  JoinQueue(String)
  TicketJoined(Result(JoinResponse, rsvp.Error(String)))
  TicketTrackingLoaded(Result(TrackedTicket, rsvp.Error(String)))
}

pub fn init(route: router.Route) -> Model {
  Model(
    public_queue: None,
    public_location: None,
    join_attempt_token: join_attempt_for_route(route),
    join_pending: False,
    join_error: None,
    tracked_ticket: None,
  )
}

/// Update visitor state and return an optional route change for the app shell.
pub fn update(
  model: Model,
  route: router.Route,
  message: Message,
) -> #(Model, Effect(Message), Option(router.Route)) {
  case message {
    PublicQueueLoaded(result) -> {
      let details = case result {
        Ok(value) -> Some(value)
        Error(_) -> None
      }
      #(Model(..model, public_queue: details), effect_none(), None)
    }
    PublicLocationLoaded(result) -> {
      let details = case result {
        Ok(value) -> Some(value)
        Error(_) -> None
      }
      #(Model(..model, public_location: details), effect_none(), None)
    }
    JoinQueue(public_id) -> {
      case model.join_pending {
        True -> #(model, effect_none(), None)
        False if model.join_attempt_token == "" -> #(
          Model(
            ..model,
            join_error: Some(
              "This browser needs secure random support to create a private ticket link.",
            ),
          ),
          effect_none(),
          None,
        )
        False -> {
          let body =
            json.object([
              #("join_attempt_token", json.string(model.join_attempt_token)),
            ])
          #(
            Model(..model, join_pending: True, join_error: None),
            rsvp.post(
              "/api/public/queues/" <> public_id <> "/tickets",
              body,
              rsvp.expect_json(decode_join_response(), TicketJoined),
            ),
            None,
          )
        }
      }
    }
    TicketJoined(Ok(response)) -> {
      clear_join_attempt(route)
      #(
        Model(
          ..model,
          join_pending: False,
          join_error: None,
          tracked_ticket: None,
        ),
        effect_none(),
        Some(router.TicketTracking(response.tracking_token)),
      )
    }
    TicketJoined(Error(error)) -> {
      let message = case error {
        rsvp.NetworkError ->
          "We could not confirm your request. Retry here; this page will reuse the same join attempt."
        rsvp.HttpError(_) ->
          "This queue may be full, closed, or require a name. Refresh and choose an available queue."
        _ ->
          "This queue could not accept your request. Check availability and try again."
      }
      #(
        Model(..model, join_pending: False, join_error: Some(message)),
        effect_none(),
        None,
      )
    }
    TicketTrackingLoaded(Ok(ticket)) -> #(
      Model(..model, tracked_ticket: Some(ticket)),
      effect_none(),
      None,
    )
    TicketTrackingLoaded(Error(_)) -> #(
      Model(..model, tracked_ticket: None),
      effect_none(),
      None,
    )
  }
}

pub fn route_changed(model: Model, route: router.Route) -> Model {
  let join_attempt_token = case route {
    router.PublicQueue(_) -> join_attempt_for_route(route)
    _ -> model.join_attempt_token
  }
  let tracked_ticket = case route {
    router.TicketTracking(_) -> None
    _ -> model.tracked_ticket
  }
  Model(
    ..model,
    join_attempt_token:,
    tracked_ticket:,
    join_pending: False,
    join_error: None,
  )
}

pub fn route_effect(route: router.Route) -> Effect(Message) {
  case route {
    router.PublicQueue(public_id) ->
      rsvp.get(
        "/api/public/queues/" <> public_id,
        rsvp.expect_json(decode_public_queue(), PublicQueueLoaded),
      )
    router.PublicLocation(location_id) ->
      rsvp.get(
        "/api/public/locations/" <> location_id,
        rsvp.expect_json(decode_public_location(), PublicLocationLoaded),
      )
    router.TicketTracking(token) ->
      rsvp.get(
        "/api/public/tickets/" <> token,
        rsvp.expect_json(decode_tracked_ticket(), TicketTrackingLoaded),
      )
    _ -> effect_none()
  }
}

pub fn page(
  route: router.Route,
  model: Model,
  navigate: fn(router.Route) -> message,
  lift: fn(Message) -> message,
) -> Element(message) {
  case route {
    router.PublicLocation(_) -> public_location_page(model, navigate)
    router.TicketTracking(_) -> ticket_tracking_page(model)
    router.VisitorJoin | router.PublicQueue(_) ->
      public_queue_page(model, route, lift)
    _ -> visitor_queue.unavailable_page()
  }
}

fn public_queue_page(
  model: Model,
  route: router.Route,
  lift: fn(Message) -> message,
) -> Element(message) {
  html.div([attr.class("public-visitor-shell")], [
    brand(),
    case model.public_queue {
      None -> visitor_queue.unavailable_page()
      Some(details) -> {
        let public_id = case route {
          router.PublicQueue(value) -> value
          _ -> ""
        }
        visitor_queue.page(
          details.organization,
          public_id,
          details.queue,
          details.service,
          details.location,
          details.availability,
          details.scheduled_service_start_at,
          details.location_id,
          model.join_pending,
          model.join_error,
          fn(value) { lift(JoinQueue(value)) },
        )
      }
    },
  ])
}

fn public_location_page(
  model: Model,
  navigate: fn(router.Route) -> message,
) -> Element(message) {
  html.div([attr.class("public-visitor-shell")], [
    brand(),
    case model.public_location {
      None -> visitor_queue.unavailable_page()
      Some(details) ->
        visitor_queue.service_selection_page(
          details.organization,
          details.location,
          list.map(details.services, fn(service) {
            #(
              service.name,
              service.queue_name,
              service.public_id,
              service.availability,
              service.waiting_count,
            )
          }),
          navigate,
        )
    },
  ])
}

fn ticket_tracking_page(model: Model) -> Element(message) {
  html.div([attr.class("public-visitor-shell")], [
    brand(),
    case model.tracked_ticket {
      Some(ticket) ->
        visitor_queue.tracking_page(
          ticket.ticket_number,
          ticket.status,
          ticket.queue_position,
          ticket.queue,
          ticket.service,
          ticket.location,
        )
      None -> visitor_queue.unavailable_page()
    },
  ])
}

fn brand() -> Element(message) {
  html.header([attr.class("public-brand")], [
    html.span([attr.class("public-brand-mark")], [html.text("k")]),
    html.strong([], [html.text("Kewkew")]),
  ])
}

fn join_attempt_for_route(route: router.Route) -> String {
  case route {
    router.PublicQueue(public_id) -> {
      let storage_key = "kewkew_join_attempt_" <> public_id
      case web_storage.session() {
        Ok(storage) ->
          case web_storage.get_item(storage, storage_key) {
            Ok(Some(token)) -> token
            _ -> create_join_attempt(storage, storage_key)
          }
        Error(_) -> create_join_attempt_without_storage()
      }
    }
    _ -> ""
  }
}

fn create_join_attempt(
  storage: web_storage.Storage,
  storage_key: String,
) -> String {
  let token = create_join_attempt_without_storage()
  case token {
    "" -> ""
    _ -> {
      let _ = web_storage.set_item(storage, storage_key, token)
      token
    }
  }
}

fn create_join_attempt_without_storage() -> String {
  case window.crypto(window.self()) {
    Ok(crypto) -> browser_crypto.random_uuid(crypto)
    Error(Nil) -> ""
  }
}

fn clear_join_attempt(route: router.Route) -> Nil {
  case route {
    router.PublicQueue(public_id) ->
      case web_storage.session() {
        Ok(storage) ->
          web_storage.remove_item(storage, "kewkew_join_attempt_" <> public_id)
        Error(_) -> Nil
      }
    _ -> Nil
  }
}

fn decode_public_queue() -> decode.Decoder(PublicQueueDetails) {
  use organization <- decode.field("organization", decode.string)
  use location_id <- decode.field("location_id", decode.string)
  use location <- decode.field("location", decode.string)
  use service <- decode.field("service", decode.string)
  use queue <- decode.field("queue", decode.string)
  use availability_state <- decode.field("availability_state", decode.string)
  use scheduled_service_start_at <- decode.field(
    "scheduled_service_start_at",
    decode.optional(decode.string),
  )
  decode.success(PublicQueueDetails(
    organization:,
    location_id:,
    location:,
    service:,
    queue:,
    availability: visitor_queue.availability_from_string(availability_state),
    scheduled_service_start_at:,
  ))
}

fn decode_public_location() -> decode.Decoder(PublicLocationData) {
  use organization <- decode.field("organization", decode.string)
  use location <- decode.field("location", decode.string)
  use services <- decode.field(
    "services",
    decode.list(decode_public_service_choice()),
  )
  decode.success(PublicLocationData(organization:, location:, services:))
}

fn decode_public_service_choice() -> decode.Decoder(PublicServiceChoice) {
  use name <- decode.field("name", decode.string)
  use queue_name <- decode.field("queue_name", decode.string)
  use public_id <- decode.field("public_id", decode.string)
  use availability_state <- decode.field("availability_state", decode.string)
  use waiting_count <- decode.field("waiting_count", decode.int)
  decode.success(PublicServiceChoice(
    name:,
    queue_name:,
    public_id:,
    availability: visitor_queue.availability_from_string(availability_state),
    waiting_count:,
  ))
}

fn decode_join_response() -> decode.Decoder(JoinResponse) {
  use tracking_token <- decode.field("tracking_token", decode.string)
  decode.success(JoinResponse(tracking_token:))
}

fn decode_tracked_ticket() -> decode.Decoder(TrackedTicket) {
  use ticket_number <- decode.field("ticket_number", decode.int)
  use status <- decode.field("status", decode.string)
  use queue_position <- decode.field(
    "queue_position",
    decode.optional(decode.int),
  )
  use queue <- decode.field("queue", decode.string)
  use service <- decode.field("service", decode.string)
  use location <- decode.field("location", decode.string)
  decode.success(TrackedTicket(
    ticket_number:,
    status:,
    queue_position:,
    queue:,
    service:,
    location:,
  ))
}

fn effect_none() -> Effect(Message) {
  effect.none()
}

import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element, none}
import lustre/element/html
import lustre/event
import rsvp
import shared.{
  type LocationOverview, type OrganizationOverview, type ServiceOverview,
}
import shared/json as shared_json

pub type Model {
  Model(
    organization_id: String,
    location_id: String,
    service_id: String,
    name: String,
    identity_policy: String,
    capacity: String,
    error: Option(String),
  )
}

pub type Message {
  Begin(String, String, String)
  OrganizationChanged(String)
  LocationChanged(String)
  ServiceChanged(String)
  NameChanged(String)
  IdentityPolicyChanged(String)
  CapacityChanged(String)
  Save
  Cancel
  Created(Result(OrganizationOverview, rsvp.Error(String)))
}

pub fn init() -> Model {
  Model("", "", "", "", "anonymous", "", None)
}

pub fn begin(
  model: Model,
  org_id: String,
  loc_id: String,
  service_id: String,
) -> Model {
  Model(
    ..model,
    organization_id: org_id,
    location_id: loc_id,
    service_id:,
    error: None,
  )
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    Begin(org_id, loc_id, service_id) -> #(
      begin(model, org_id, loc_id, service_id),
      effect.none(),
    )
    OrganizationChanged(organization_id) -> #(
      Model(
        ..model,
        organization_id:,
        location_id: "",
        service_id: "",
        error: None,
      ),
      effect.none(),
    )
    LocationChanged(location_id) -> #(
      Model(..model, location_id:, service_id: "", error: None),
      effect.none(),
    )
    ServiceChanged(service_id) -> #(
      Model(..model, service_id:, error: None),
      effect.none(),
    )
    NameChanged(name) -> #(Model(..model, name:, error: None), effect.none())
    IdentityPolicyChanged(identity_policy) -> #(
      Model(..model, identity_policy:, error: None),
      effect.none(),
    )
    CapacityChanged(capacity) -> #(
      Model(..model, capacity:, error: None),
      effect.none(),
    )
    Save -> save(model)
    Cancel -> #(init(), effect.none())
    Created(Ok(_)) -> #(init(), effect.none())
    Created(Error(_)) -> #(
      Model(
        ..model,
        error: Some(
          "We couldn't create the queue. Check the settings and try again.",
        ),
      ),
      effect.none(),
    )
  }
}

pub fn overview_from_message(message: Message) -> Option(OrganizationOverview) {
  case message {
    Created(Ok(overview)) -> Some(overview)
    _ -> None
  }
}

fn save(model: Model) -> #(Model, Effect(Message)) {
  let name = string.trim(model.name)
  let capacity = case string.trim(model.capacity) {
    "" -> Ok(None)
    value ->
      case int.parse(value) {
        Ok(number) if number > 0 -> Ok(Some(number))
        _ -> Error(Nil)
      }
  }
  case
    name,
    model.organization_id,
    model.location_id,
    model.service_id,
    capacity
  {
    "", _, _, _, _ -> validation_error(model, "Enter a queue name.")
    _, "", _, _, _ -> validation_error(model, "Choose an organization.")
    _, _, "", _, _ -> validation_error(model, "Choose a location.")
    _, _, _, "", _ -> validation_error(model, "Choose a service.")
    _, _, _, _, Error(_) ->
      validation_error(model, "Capacity must be a positive whole number.")
    _, org_id, loc_id, service_id, Ok(capacity) -> {
      let body =
        json.object([
          #("name", json.string(name)),
          #("identity_policy", json.string(model.identity_policy)),
          #("active_ticket_capacity", json.nullable(capacity, json.int)),
        ])
      let path =
        "/api/organizations/"
        <> org_id
        <> "/locations/"
        <> loc_id
        <> "/services/"
        <> service_id
        <> "/queues"
      #(
        model,
        rsvp.post(
          path,
          body,
          rsvp.expect_json(shared_json.organization_overview_decoder(), Created),
        ),
      )
    }
  }
}

fn validation_error(
  model: Model,
  message: String,
) -> #(Model, Effect(Message)) {
  #(Model(..model, error: Some(message)), effect.none())
}

pub fn view(
  model: Model,
  overviews: Option(List(OrganizationOverview)),
  lift: fn(Message) -> message,
) -> Element(message) {
  let organizations = case overviews {
    Some(values) -> list.filter(values, fn(value) { value.can_manage })
    None -> []
  }
  case organizations {
    [] ->
      html.section([attr.class("card setup-card")], [
        html.div([attr.class("empty-state")], [
          html.h3([], [html.text("Administrator access required")]),
          html.p([], [
            html.text("Only organization administrators can create queues."),
          ]),
        ]),
      ])
    _ -> queue_form(model, organizations, lift)
  }
}

fn queue_form(
  model: Model,
  organizations: List(OrganizationOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  let selected_org = find_organization(organizations, model.organization_id)
  let locations = case selected_org {
    Some(overview) -> overview.locations
    None -> []
  }
  let selected_location = find_location(locations, model.location_id)
  let services = case selected_location {
    Some(location) -> location.services
    None -> []
  }
  html.section([], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Queue configuration")]),
        html.h1([], [html.text("Create a queue")]),
        html.p([attr.class("subhead")], [
          html.text(
            "Set up a queue for a service. It will remain inactive until you enable it and open a session.",
          ),
        ]),
      ]),
    ]),
    html.div([attr.class("settings-layout")], [
      html.form(
        [
          attr.class("settings-card card queue-create-form"),
          event.on_submit(fn(_) { lift(Save) }),
        ],
        [
          html.label([attr.class("field")], [
            html.text("Queue name"),
            html.input([
              attr.attribute("value", model.name),
              attr.attribute("aria-label", "Queue name"),
              attr.required(True),
              event.on_input(fn(value) { lift(NameChanged(value)) }),
            ]),
          ]),
          organization_select(model, organizations, lift),
          location_select(model, locations, lift),
          service_select(model, services, lift),
          html.label([attr.class("field")], [
            html.text("Visitor identity"),
            html.select(
              [
                attr.attribute("aria-label", "Visitor identity"),
                attr.required(True),
                event.on_input(fn(value) { lift(IdentityPolicyChanged(value)) }),
              ],
              [
                html.option(
                  [
                    attr.attribute("value", "anonymous"),
                    attr.selected(model.identity_policy == "anonymous"),
                  ],
                  "Anonymous ticket",
                ),
                html.option(
                  [
                    attr.attribute("value", "name_required"),
                    attr.selected(model.identity_policy == "name_required"),
                  ],
                  "First and last name required",
                ),
              ],
            ),
          ]),
          html.label([attr.class("field")], [
            html.text("Maximum active tickets (optional)"),
            html.input([
              attr.attribute("type", "number"),
              attr.attribute("min", "1"),
              attr.attribute("step", "1"),
              attr.attribute("value", model.capacity),
              attr.attribute("aria-label", "Maximum active tickets (optional)"),
              event.on_input(fn(value) { lift(CapacityChanged(value)) }),
            ]),
          ]),
          html.div([attr.class("location-form-actions")], [
            html.button(
              [
                attr.class("quiet"),
                attr.attribute("type", "button"),
                event.on_click(lift(Cancel)),
              ],
              [html.text("Cancel")],
            ),
            html.button(
              [attr.class("primary"), attr.attribute("type", "submit")],
              [html.text("Create queue")],
            ),
          ]),
          case model.error {
            Some(message) ->
              html.p(
                [attr.class("sign-in-error"), attr.attribute("role", "alert")],
                [html.text(message)],
              )
            None -> none()
          },
        ],
      ),
      html.aside([attr.class("preview-card")], [
        html.p([attr.class("preview-label")], [html.text("Queue setup")]),
        html.h3([], [html.text("Ready for your next operating session")]),
        html.p([attr.class("muted")], [
          html.text(
            "Creating a queue saves its configuration only. No session is opened and visitors cannot join until the queue is activated and staff open a session.",
          ),
        ]),
      ]),
    ]),
  ])
}

fn organization_select(
  model: Model,
  organizations: List(OrganizationOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  html.label([attr.class("field")], [
    html.text("Organization"),
    html.select(
      [
        attr.attribute("aria-label", "Organization"),
        attr.required(True),
        event.on_input(fn(value) { lift(OrganizationChanged(value)) }),
      ],
      [
        html.option(
          [
            attr.attribute("value", ""),
            attr.selected(model.organization_id == ""),
            attr.disabled(True),
          ],
          "Choose organization",
        ),
        ..list.map(organizations, fn(overview) {
          html.option(
            [
              attr.attribute("value", overview.organization.id),
              attr.selected(model.organization_id == overview.organization.id),
            ],
            overview.organization.name,
          )
        })
      ],
    ),
  ])
}

fn location_select(
  model: Model,
  locations: List(LocationOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  html.label([attr.class("field")], [
    html.text("Location"),
    html.select(
      [
        attr.attribute("aria-label", "Location"),
        attr.required(True),
        event.on_input(fn(value) { lift(LocationChanged(value)) }),
      ],
      [
        html.option(
          [
            attr.attribute("value", ""),
            attr.selected(model.location_id == ""),
            attr.disabled(True),
          ],
          "Choose location",
        ),
        ..list.map(locations, fn(location) {
          html.option(
            [
              attr.attribute("value", location.location.id),
              attr.selected(model.location_id == location.location.id),
            ],
            location.location.name,
          )
        })
      ],
    ),
  ])
}

fn service_select(
  model: Model,
  services: List(ServiceOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  html.label([attr.class("field")], [
    html.text("Service"),
    html.select(
      [
        attr.attribute("aria-label", "Service"),
        attr.required(True),
        event.on_input(fn(value) { lift(ServiceChanged(value)) }),
      ],
      [
        html.option(
          [
            attr.attribute("value", ""),
            attr.selected(model.service_id == ""),
            attr.disabled(True),
          ],
          "Choose service",
        ),
        ..list.map(services, fn(service) {
          html.option(
            [
              attr.attribute("value", service.service.id),
              attr.selected(model.service_id == service.service.id),
            ],
            service.service.name,
          )
        })
      ],
    ),
  ])
}

fn find_organization(
  organizations: List(OrganizationOverview),
  id: String,
) -> Option(OrganizationOverview) {
  case list.filter(organizations, fn(value) { value.organization.id == id }) {
    [value, ..] -> Some(value)
    [] -> None
  }
}

fn find_location(
  locations: List(LocationOverview),
  id: String,
) -> Option(LocationOverview) {
  case list.filter(locations, fn(value) { value.location.id == id }) {
    [value, ..] -> Some(value)
    [] -> None
  }
}

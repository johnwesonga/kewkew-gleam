import client/router
import client/visitor_flow as flow
import client/visitor_queue
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/effect
import lustre/element
import rsvp

fn ticket(status: String) -> flow.TrackedTicket {
  flow.TrackedTicket(
    organization: "Kewkew",
    ticket_number: 42,
    status: status,
    queue_position: Some(3),
    queue: "Support queue",
    service: "Food support",
    location: "Downtown",
    visitor_first_name: Some("Private name"),
    visitor_instructions: Some("Go to counter 4"),
    scheduled_service_start_at: Some("Tomorrow at 9"),
  )
}

fn render(model: flow.Model) -> String {
  flow.page(router.TicketTracking("private-token"), model, fn(_) { Nil }, fn(_) {
    Nil
  })
  |> element.to_string
}

fn assert_receipt(markup: String) {
  list.each(
    [
      "Thank you for visiting",
      "Service complete for ticket #42",
      "Food support",
      "Downtown",
      "You can leave now",
      "role=\"status\"",
      "aria-live=\"polite\"",
    ],
    fn(text) { string.contains(markup, text) |> should.be_true },
  )
  list.each(
    [
      "Position in line",
      "Leave queue",
      "Copy private tracking link",
      "Private name",
      "Go to counter 4",
      "Tomorrow at 9",
      "automatically",
      "You are ticket",
      "private-token",
    ],
    fn(text) { string.contains(markup, text) |> should.be_false },
  )
}

pub fn completion_replaces_open_ticket_and_stops_polling_test() {
  let route = router.TicketTracking("private-token")
  let #(waiting, _, _) =
    flow.update(
      flow.init(route),
      route,
      flow.TicketTrackingLoaded("private-token", Ok(ticket("waiting"))),
    )
  render(waiting) |> string.contains("Position in line: 3") |> should.be_true
  let #(completed, pending, navigation) =
    flow.update(
      waiting,
      route,
      flow.TicketTrackingLoaded("private-token", Ok(ticket("completed"))),
    )
  assert_receipt(render(completed))
  pending |> should.equal(effect.none())
  navigation |> should.equal(None)
  let #(unchanged, pending, _) =
    flow.update(completed, route, flow.RefreshTicketTracking("private-token"))
  assert_receipt(render(unchanged))
  pending |> should.equal(effect.none())
}

pub fn reopening_private_url_loads_completion_receipt_test() {
  let route = router.TicketTracking("private-token")
  let #(model, pending, navigation) =
    flow.update(
      flow.init(route),
      route,
      flow.TicketTrackingLoaded("private-token", Ok(ticket("completed"))),
    )
  assert_receipt(render(model))
  pending |> should.equal(effect.none())
  navigation |> should.equal(None)
  list.each([rsvp.NetworkError, rsvp.BadBody], fn(error) {
    let #(retained, pending, _) =
      flow.update(
        model,
        route,
        flow.TicketTrackingLoaded("private-token", Error(error)),
      )
    assert_receipt(render(retained))
    pending |> should.equal(effect.none())
  })
}

pub fn completion_hides_stale_controls_notices_and_personal_details_test() {
  visitor_queue.tracking_page(
    "Kewkew",
    42,
    "completed",
    Some(3),
    "Food support",
    "Downtown",
    Some("Tomorrow at 9"),
    Some("Private name"),
    Some("Go to counter 4"),
    "private-token",
    Some("Copied"),
    fn(_) { Nil },
    Some("Retrying"),
    True,
    Some("Failed"),
    fn() { Nil },
    True,
    fn(_) { Nil },
  )
  |> element.to_string
  |> assert_receipt
}

pub fn unsuccessful_terminal_states_keep_their_own_guidance_test() {
  list.each(
    [
      #("cancelled", "You left this queue"),
      #("no_show", "Your call was missed"),
    ],
    fn(state) {
      let #(status, guidance) = state
      let route = router.TicketTracking("private-token")
      let #(model, _, _) =
        flow.update(
          flow.init(route),
          route,
          flow.TicketTrackingLoaded("private-token", Ok(ticket(status))),
        )
      let markup = render(model)
      string.contains(markup, guidance) |> should.be_true
      string.contains(markup, "Thank you for visiting") |> should.be_false
      string.contains(markup, "Service complete") |> should.be_false
    },
  )
}

pub fn late_active_response_cannot_replace_completion_receipt_test() {
  let route = router.TicketTracking("private-token")
  let #(model, _, _) =
    flow.update(
      flow.init(route),
      route,
      flow.TicketTrackingLoaded("private-token", Ok(ticket("completed"))),
    )
  let #(retained, pending, navigation) =
    flow.update(
      model,
      route,
      flow.TicketTrackingLoaded("private-token", Ok(ticket("waiting"))),
    )
  assert_receipt(render(retained))
  pending |> should.equal(effect.none())
  navigation |> should.equal(None)
}

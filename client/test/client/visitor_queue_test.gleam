import client/visitor_queue
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element
import shared.{Anonymous, NameRequired}

pub fn open_state_allows_join_and_has_open_copy_test() {
  let state = visitor_queue.availability_from_string("open")
  state |> should.equal(visitor_queue.Open)
  visitor_queue.join_enabled(state) |> should.be_true
  visitor_queue.title(state) |> should.equal("Signup is open")
  visitor_queue.explanation(state)
  |> should.equal("This queue is ready for visitors to join.")
}

pub fn paused_state_blocks_join_and_explains_pause_test() {
  let state = visitor_queue.availability_from_string("paused")
  state |> should.equal(visitor_queue.Paused)
  visitor_queue.join_enabled(state) |> should.be_false
  visitor_queue.title(state) |> should.equal("Signup is paused")
  visitor_queue.explanation(state)
  |> should.equal("Joining is temporarily paused. Please check again soon.")
}

pub fn full_state_blocks_join_and_explains_capacity_test() {
  let state = visitor_queue.availability_from_string("full")
  state |> should.equal(visitor_queue.Full)
  visitor_queue.join_enabled(state) |> should.be_false
  visitor_queue.title(state) |> should.equal("Queue is full")
  visitor_queue.explanation(state)
  |> should.equal("This queue has reached its current capacity.")
}

pub fn closed_and_unknown_states_block_join_without_fake_reopening_time_test() {
  let closed = visitor_queue.availability_from_string("closed")
  closed |> should.equal(visitor_queue.Closed)
  visitor_queue.join_enabled(closed) |> should.be_false
  visitor_queue.title(closed) |> should.equal("Signup is closed")
  visitor_queue.explanation(closed)
  |> should.equal("This queue is not accepting visitors right now.")

  let unknown = visitor_queue.availability_from_string("unexpected")
  unknown |> should.equal(visitor_queue.Closed)
  visitor_queue.join_enabled(unknown) |> should.be_false
}

pub fn valid_queue_page_shows_business_service_location_and_open_join_action_test() {
  let markup =
    visitor_queue.page(
      "FireFly",
      "public-queue",
      "Test Queue",
      "Clothes line",
      "W-Salem",
      visitor_queue.Open,
      Some("Wednesday, Nov 4, 2026, 3:00 PM · Africa/Nairobi"),
      "location-1",
      Anonymous,
      "",
      "",
      False,
      fn(_) { Nil },
      fn(_) { Nil },
      False,
      None,
      fn(_) { Nil },
    )
    |> element.to_string

  let assert True = string.contains(markup, "FireFly")
  let assert True = string.contains(markup, "Test Queue")
  let assert True = string.contains(markup, "Clothes line · W-Salem")
  let assert True = string.contains(markup, "Signup is open")
  let assert True = string.contains(markup, "Join this queue")
  let assert True = string.contains(markup, "role=\"status\"")
  let assert True = string.contains(markup, "<button")
  let assert True = string.contains(markup, "Scheduled service start")
  let assert True = string.contains(markup, "/l/location-1")
  let assert True = string.contains(markup, "Africa/Nairobi")
  let assert False = string.contains(markup, "First name")
  let assert False = string.contains(markup, "Last name")
  let assert False = string.contains(markup, "email")
  let assert False = string.contains(markup, "disabled")
}

pub fn anonymous_join_button_disables_while_pending_and_shows_error_test() {
  let markup =
    visitor_queue.page(
      "FireFly",
      "public-queue",
      "Test Queue",
      "Clothes line",
      "W-Salem",
      visitor_queue.Open,
      None,
      "location-1",
      Anonymous,
      "",
      "",
      False,
      fn(_) { Nil },
      fn(_) { Nil },
      True,
      Some("This queue is no longer accepting visitors."),
      fn(_) { Nil },
    )
    |> element.to_string

  let assert True = string.contains(markup, "Joining…")
  let assert True = string.contains(markup, "disabled")
  let assert True = string.contains(markup, "role=\"alert\"")
  let assert True = string.contains(markup, "no longer accepting")
}

pub fn private_ticket_page_shows_number_status_and_position_test() {
  let markup =
    visitor_queue.tracking_page(
      "Mandugu Digital",
      7,
      "waiting",
      Some(2),
      "Food support",
      "Downtown",
      Some("Wednesday, Nov 18, 2026, 11:30 PM · America/Los_Angeles"),
      None,
      None,
      "http://localhost:1234/t/private-token",
      None,
      fn(_) { Nil },
      None,
      False,
      None,
      fn() { Nil },
      False,
      fn(_) { Nil },
    )
    |> element.to_string

  let assert True = string.contains(markup, "You are ticket #7")
  let assert True = string.contains(markup, "Position in line: 2")
  let assert True = string.contains(markup, "Food support · Downtown")
  let assert True = string.contains(markup, "Mandugu Digital")
  let assert True = string.contains(markup, "Scheduled service start")
  let assert True = string.contains(markup, "I want to leave this queue.")
  let assert True =
    string.contains(markup, "ticket number is not a tracking credential")
  let assert True = string.contains(markup, "Copy private tracking link")
  let assert True = string.contains(markup, "Leave queue")
  let assert True = string.contains(markup, "expires 24 hours")
  let assert False =
    string.contains(markup, "http://localhost:1234/t/private-token")
  let assert True = string.contains(markup, "disabled")
}

pub fn tracking_page_shows_copy_confirmation_test() {
  let markup =
    visitor_queue.tracking_page(
      "Kewkew",
      9,
      "waiting",
      Some(1),
      "Support",
      "Downtown",
      None,
      None,
      None,
      "https://example.test/t/private-token",
      Some("Private tracking link copied."),
      fn(_) { Nil },
      None,
      False,
      None,
      fn() { Nil },
      False,
      fn(_) { Nil },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Private tracking link copied.")
}

pub fn tracking_page_explains_automatic_updates_until_ticket_is_terminal_test() {
  let active =
    visitor_queue.tracking_page(
      "Kewkew",
      10,
      "called",
      None,
      "Support",
      "Downtown",
      None,
      None,
      Some("Go to counter 4 and show staff your number."),
      "https://example.test/t/active",
      None,
      fn(_) { Nil },
      None,
      False,
      None,
      fn() { Nil },
      False,
      fn(_) { Nil },
    )
    |> element.to_string
  let terminal =
    visitor_queue.tracking_page(
      "Kewkew",
      10,
      "completed",
      None,
      "Support",
      "Downtown",
      None,
      None,
      None,
      "https://example.test/t/completed",
      None,
      fn(_) { Nil },
      None,
      False,
      None,
      fn() { Nil },
      False,
      fn(_) { Nil },
    )
    |> element.to_string
  let assert True =
    string.contains(active, "update automatically every 5 seconds")
  let assert True = string.contains(active, "called-ticket-next-step")
  let assert True = string.contains(active, "Go to counter 4")
  let assert False = string.contains(active, "Leave queue")
  let assert True = string.contains(active, "ask staff if you need help")
  let assert False =
    string.contains(terminal, "update automatically every 5 seconds")
  let assert False = string.contains(terminal, "Leave queue")
}

pub fn no_show_tracking_page_explains_the_missed_call_next_step_test() {
  let markup =
    visitor_queue.tracking_page(
      "Kewkew",
      11,
      "no_show",
      None,
      "Support",
      "Downtown",
      None,
      None,
      None,
      "https://example.test/t/no-show",
      None,
      fn(_) { Nil },
      None,
      False,
      None,
      fn() { Nil },
      False,
      fn(_) { Nil },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Marked as a no-show")
  let assert True = string.contains(markup, "Your call was missed")
  let assert False = string.contains(markup, "Leave queue")
}

pub fn called_ticket_uses_clear_default_when_service_has_no_instructions_test() {
  let markup =
    visitor_queue.tracking_page(
      "Kewkew",
      12,
      "called",
      None,
      "Support",
      "Downtown",
      None,
      None,
      None,
      "https://example.test/t/called",
      None,
      fn(_) { Nil },
      None,
      False,
      None,
      fn() { Nil },
      False,
      fn(_) { Nil },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Your number was called")
  let assert True = string.contains(markup, "Please go to the service desk")
  let assert True = string.contains(markup, "aria-live=\"assertive\"")
}

pub fn private_ticket_page_identifies_name_required_visitor_by_first_name_test() {
  let markup =
    visitor_queue.tracking_page(
      "Kewkew",
      8,
      "waiting",
      Some(1),
      "Support",
      "Downtown",
      None,
      Some("Alex"),
      None,
      "https://example.test/t/token",
      None,
      fn(_) { Nil },
      None,
      False,
      None,
      fn() { Nil },
      False,
      fn(_) { Nil },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Welcome, Alex")
}

pub fn unavailable_link_page_does_not_expose_queue_details_test() {
  let markup = visitor_queue.unavailable_page() |> element.to_string
  let assert True = string.contains(markup, "Queue unavailable")
  let assert True = string.contains(markup, "invalid or no longer active")
  let assert False = string.contains(markup, "FireFly")
  let assert False = string.contains(markup, "Test Queue")
  let assert False = string.contains(markup, "Join this queue")
}

pub fn unavailable_queue_page_disables_native_join_button_test() {
  let markup =
    visitor_queue.page(
      "FireFly",
      "public-queue",
      "Test Queue",
      "Clothes line",
      "W-Salem",
      visitor_queue.Closed,
      None,
      "location-1",
      Anonymous,
      "",
      "",
      False,
      fn(_) { Nil },
      fn(_) { Nil },
      False,
      None,
      fn(_) { Nil },
    )
    |> element.to_string

  let assert True = string.contains(markup, "Signup is closed")
  let assert True = string.contains(markup, "Joining unavailable")
  let assert True = string.contains(markup, "disabled")
}

pub fn name_required_queue_shows_labeled_fields_and_missing_field_errors_test() {
  let markup =
    visitor_queue.page(
      "Kewkew",
      "public-queue",
      "Main line",
      "Support",
      "Downtown",
      visitor_queue.Open,
      None,
      "location-1",
      NameRequired,
      "",
      "",
      True,
      fn(_) { Nil },
      fn(_) { Nil },
      False,
      None,
      fn(_) { Nil },
    )
    |> element.to_string
  let assert True = string.contains(markup, "First name")
  let assert True = string.contains(markup, "Last name")
  let assert True = string.contains(markup, "First name is required")
  let assert True = string.contains(markup, "Last name is required")
  let assert True = string.contains(markup, "autocomplete=\"given-name\"")
  let assert True = string.contains(markup, "autocomplete=\"family-name\"")
}

pub fn service_selection_shows_queue_info_and_disables_unavailable_choice_test() {
  let markup =
    visitor_queue.service_selection_page(
      "Kewkew Test",
      "Downtown",
      [
        #("Food support", "Food line", "food-public", visitor_queue.Open, 3),
        #(
          "Housing help",
          "Housing line",
          "housing-public",
          visitor_queue.Closed,
          0,
        ),
      ],
      fn(route) { route },
    )
    |> element.to_string

  let assert True = string.contains(markup, "Choose a queue")
  let assert True = string.contains(markup, "Food support")
  let assert True = string.contains(markup, "Food line")
  let assert True =
    string.contains(markup, "Open · " <> int.to_string(3) <> " waiting")
  let assert True = string.contains(markup, "Housing help")
  let assert True = string.contains(markup, "Signup is closed")
  let assert True = string.contains(markup, "disabled")
  let assert True = string.contains(markup, "Choose queue")
}

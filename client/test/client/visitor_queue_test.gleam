import client/visitor_queue
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

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
      "Test Queue",
      "Clothes line",
      "W-Salem",
      visitor_queue.Open,
      Some("Wednesday, Nov 4, 2026, 3:00 PM · Africa/Nairobi"),
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
  let assert True = string.contains(markup, "Africa/Nairobi")
  let assert False = string.contains(markup, "disabled")
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
      "Test Queue",
      "Clothes line",
      "W-Salem",
      visitor_queue.Closed,
      None,
    )
    |> element.to_string

  let assert True = string.contains(markup, "Signup is closed")
  let assert True = string.contains(markup, "Joining unavailable")
  let assert True = string.contains(markup, "disabled")
}

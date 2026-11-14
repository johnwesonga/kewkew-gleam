import client/visitor_queue
import gleeunit/should

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

/// Visitor-facing availability states for a public queue.
pub type Availability {
  Open
  Paused
  Full
  Closed
}

/// Convert the public API state into a safe visitor-facing state.
pub fn availability_from_string(value: String) -> Availability {
  case value {
    "open" -> Open
    "paused" -> Paused
    "full" -> Full
    _ -> Closed
  }
}

/// Whether the public page may offer the join action.
pub fn join_enabled(availability: Availability) -> Bool {
  availability == Open
}

/// Short status heading displayed to visitors.
pub fn title(availability: Availability) -> String {
  case availability {
    Open -> "Signup is open"
    Paused -> "Signup is paused"
    Full -> "Queue is full"
    Closed -> "Signup is closed"
  }
}

/// Explain the current state without inventing reopening information.
pub fn explanation(availability: Availability) -> String {
  case availability {
    Open -> "This queue is ready for visitors to join."
    Paused -> "Joining is temporarily paused. Please check again soon."
    Full -> "This queue has reached its current capacity."
    Closed -> "This queue is not accepting visitors right now."
  }
}

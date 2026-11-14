import gleam/option.{type Option, None, Some}
import lustre/attribute as attr
import lustre/element as element_module
import lustre/element/html

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

/// Render the public visitor information card for a resolved queue link.
pub fn page(
  organization: String,
  queue: String,
  service: String,
  location: String,
  availability: Availability,
  scheduled_service_start_at: Option(String),
) -> element_module.Element(message) {
  let available = join_enabled(availability)
  html.section([attr.class("public-queue-card card")], [
    html.p([attr.class("public-organization")], [html.text(organization)]),
    html.h1([], [html.text(queue)]),
    html.p([attr.class("public-location")], [
      html.text(service <> " · " <> location),
    ]),
    case scheduled_service_start_at {
      Some(start) ->
        html.div([attr.class("schedule-callout")], [
          html.strong([], [html.text("Scheduled service start")]),
          html.p([], [html.text(start)]),
        ])
      None -> element_module.none()
    },
    html.div(
      [
        attr.classes([
          #("availability-callout", True),
          #("closed", !available),
        ]),
        attr.attribute("role", "status"),
      ],
      [
        html.span(
          [
            attr.class("availability-dot"),
            attr.attribute("aria-hidden", "true"),
          ],
          [],
        ),
        html.div([], [
          html.strong([], [html.text(title(availability))]),
          html.p([], [html.text(explanation(availability))]),
        ]),
      ],
    ),
    html.button(
      [
        attr.class("primary public-join-button"),
        attr.disabled(!available),
      ],
      [
        html.text(case available {
          True -> "Join this queue"
          False -> "Joining unavailable"
        }),
      ],
    ),
    html.p([attr.class("public-privacy-note")], [
      html.text(
        "This page is public queue information. It does not provide access to staff tools or private ticket tracking.",
      ),
    ]),
  ])
}

/// Render a generic unavailable state without revealing queue data.
pub fn unavailable_page() -> element_module.Element(message) {
  html.section([attr.class("public-queue-card card")], [
    html.h1([], [html.text("Queue unavailable")]),
    html.p([], [
      html.text("This queue link may be invalid or no longer active."),
    ]),
  ])
}

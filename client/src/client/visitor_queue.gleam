import client/router
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/element as element_module
import lustre/element/html
import lustre/event
import shared.{type IdentityPolicy, Anonymous, NameRequired}

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
  public_id: String,
  queue: String,
  service: String,
  location: String,
  availability: Availability,
  scheduled_service_start_at: Option(String),
  location_id: String,
  identity_policy: IdentityPolicy,
  first_name: String,
  last_name: String,
  show_name_errors: Bool,
  first_name_changed: fn(String) -> message,
  last_name_changed: fn(String) -> message,
  join_pending: Bool,
  join_error: Option(String),
  join: fn(String) -> message,
) -> element_module.Element(message) {
  let available = join_enabled(availability)
  html.section([attr.class("public-queue-card card")], [
    html.p([attr.class("public-organization")], [html.text(organization)]),
    html.h1([], [html.text(queue)]),
    html.p([attr.class("public-location")], [
      html.text(service <> " · " <> location),
    ]),
    html.a(
      [
        attr.class("public-browse-services"),
        attr.attribute(
          "href",
          router.to_path(router.PublicLocation(location_id)),
        ),
      ],
      [html.text("See other services at this location")],
    ),
    case scheduled_service_start_at {
      Some(start) ->
        html.div([attr.class("schedule-callout")], [
          html.strong([], [html.text("Scheduled service start")]),
          html.p([], [html.text(start)]),
        ])
      None -> element_module.none()
    },
    case identity_policy {
      Anonymous -> element_module.none()
      NameRequired ->
        html.div([attr.class("visitor-name-fields")], [
          html.label([attr.class("field")], [
            html.span([], [html.text("First name")]),
            html.input([
              attr.type_("text"),
              attr.value(first_name),
              attr.attribute("autocomplete", "given-name"),
              event.on_input(first_name_changed),
            ]),
            case show_name_errors && string.trim(first_name) == "" {
              True ->
                html.span(
                  [attr.class("field-error"), attr.attribute("role", "alert")],
                  [html.text("First name is required")],
                )
              False -> element_module.none()
            },
          ]),
          html.label([attr.class("field")], [
            html.span([], [html.text("Last name")]),
            html.input([
              attr.type_("text"),
              attr.value(last_name),
              attr.attribute("autocomplete", "family-name"),
              event.on_input(last_name_changed),
            ]),
            case show_name_errors && string.trim(last_name) == "" {
              True ->
                html.span(
                  [attr.class("field-error"), attr.attribute("role", "alert")],
                  [html.text("Last name is required")],
                )
              False -> element_module.none()
            },
          ]),
        ])
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
        attr.disabled(!available || join_pending),
        event.on_click(join(public_id)),
      ],
      [
        html.text(case available, join_pending {
          True, True -> "Joining…"
          True, False -> "Join this queue"
          False, _ -> "Joining unavailable"
        }),
      ],
    ),
    case join_error {
      Some(message) ->
        html.p([attr.class("sign-in-error"), attr.attribute("role", "alert")], [
          html.text(message),
        ])
      None -> element_module.none()
    },
    html.p([attr.class("public-privacy-note")], [
      html.text(
        "This page is public queue information. It does not provide access to staff tools or private ticket tracking.",
      ),
    ]),
  ])
}

pub fn tracking_page(
  organization: String,
  ticket_number: Int,
  status: String,
  queue_position: Option(Int),
  service: String,
  location: String,
  scheduled_service_start_at: Option(String),
  visitor_first_name: Option(String),
  visitor_instructions: Option(String),
  tracking_url: String,
  copy_status: Option(String),
  copy_link: fn(String) -> message,
  tracking_notice: Option(String),
  cancel_pending: Bool,
  cancel_error: Option(String),
  cancel_ticket: fn() -> message,
  cancel_confirmed: Bool,
  cancel_confirmation_changed: fn(Bool) -> message,
) -> element_module.Element(message) {
  case status {
    "completed" ->
      completion_page(organization, ticket_number, service, location)
    _ ->
      active_tracking_page(
        organization,
        ticket_number,
        status,
        queue_position,
        service,
        location,
        scheduled_service_start_at,
        visitor_first_name,
        visitor_instructions,
        tracking_url,
        copy_status,
        copy_link,
        tracking_notice,
        cancel_pending,
        cancel_error,
        cancel_ticket,
        cancel_confirmed,
        cancel_confirmation_changed,
      )
  }
}

fn completion_page(
  organization: String,
  ticket_number: Int,
  service: String,
  location: String,
) -> element_module.Element(message) {
  html.section([attr.class("public-queue-card card ticket-completion")], [
    html.p([attr.class("ticket-context")], [
      html.strong([], [html.text(organization)]),
      html.span([], [html.text(service <> " · " <> location)]),
    ]),
    html.div(
      [
        attr.class("availability-callout"),
        attr.attribute("role", "status"),
        attr.attribute("aria-live", "polite"),
      ],
      [
        html.div([], [
          html.h1([], [html.text("Thank you for visiting")]),
          html.p([], [
            html.text(
              "Service complete for ticket #"
              <> int.to_string(ticket_number)
              <> ".",
            ),
          ]),
          html.p([], [
            html.text(
              "You can leave now. You no longer need to monitor your place in line.",
            ),
          ]),
        ]),
      ],
    ),
  ])
}

fn active_tracking_page(
  organization: String,
  ticket_number: Int,
  status: String,
  queue_position: Option(Int),
  service: String,
  location: String,
  scheduled_service_start_at: Option(String),
  visitor_first_name: Option(String),
  visitor_instructions: Option(String),
  tracking_url: String,
  copy_status: Option(String),
  copy_link: fn(String) -> message,
  tracking_notice: Option(String),
  cancel_pending: Bool,
  cancel_error: Option(String),
  cancel_ticket: fn() -> message,
  cancel_confirmed: Bool,
  cancel_confirmation_changed: fn(Bool) -> message,
) -> element_module.Element(message) {
  html.section([attr.class("public-queue-card card")], [
    html.p([attr.class("ticket-context")], [
      html.strong([], [html.text(organization)]),
      html.span([], [html.text(service <> " · " <> location)]),
    ]),
    html.h2([], [html.text("You are ticket #" <> int.to_string(ticket_number))]),
    case scheduled_service_start_at {
      Some(start) ->
        html.div([attr.class("schedule-callout")], [
          html.strong([], [html.text("Scheduled service start")]),
          html.p([], [html.text(start)]),
        ])
      None -> element_module.none()
    },
    case visitor_first_name {
      Some(name) ->
        html.p([attr.class("visitor-confirmation")], [
          html.text("Welcome, " <> name <> "."),
        ])
      None -> element_module.none()
    },
    html.div(
      [
        attr.classes([
          #("availability-callout", True),
          #("called", status == "called"),
          #("serving", status == "serving"),
          #("no-show", status == "no_show"),
        ]),
        attr.attribute("role", "status"),
        attr.attribute("aria-live", "polite"),
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
          html.strong([], [html.text(ticket_status_label(status))]),
          status_guidance(status, visitor_instructions),
          case status, queue_position {
            "waiting", Some(position) ->
              html.p([], [
                html.text("Position in line: " <> int.to_string(position)),
              ])
            _, _ -> element_module.none()
          },
        ]),
      ],
    ),
    case tracking_notice {
      Some(notice) ->
        html.p([attr.class("muted"), attr.attribute("role", "status")], [
          html.text(notice),
        ])
      None ->
        case status {
          "waiting" | "called" | "serving" ->
            html.p([attr.class("muted")], [
              html.text(
                "Ticket status and position update automatically every 5 seconds.",
              ),
            ])
          _ -> element_module.none()
        }
    },
    case status {
      "waiting" ->
        html.div([attr.class("visitor-cancel-action")], [
          html.hr([]),
          html.label([attr.class("visitor-leave-confirmation")], [
            html.input([
              attr.type_("checkbox"),
              attr.checked(cancel_confirmed),
              attr.disabled(cancel_pending),
              event.on_check(cancel_confirmation_changed),
            ]),
            html.span([], [html.text("I want to leave this queue.")]),
          ]),
          html.button(
            [
              attr.class("visitor-leave-button"),
              attr.disabled(cancel_pending || !cancel_confirmed),
              event.on_click(cancel_ticket()),
            ],
            [
              html.text(case cancel_pending {
                True -> "Leaving queue…"
                False -> "Leave queue"
              }),
            ],
          ),
          case cancel_error {
            Some(message) ->
              html.p(
                [attr.class("sign-in-error"), attr.attribute("role", "alert")],
                [html.text(message)],
              )
            None -> element_module.none()
          },
        ])
      "called" | "serving" ->
        html.p([attr.class("muted")], [
          html.text(
            "You can leave the queue while waiting. Your turn has started, so ask staff if you need help.",
          ),
        ])
      _ -> element_module.none()
    },
    html.div([attr.class("private-tracking-link")], [
      html.button(
        [
          attr.class("visitor-copy-link"),
          event.on_click(copy_link(tracking_url)),
        ],
        [html.text("Copy private tracking link")],
      ),
      case copy_status {
        Some(message) ->
          html.p([attr.attribute("role", "status")], [html.text(message)])
        None -> element_module.none()
      },
    ]),
    html.p([attr.class("public-privacy-note")], [
      html.text(
        "Your ticket updates automatically while this page is open. Save this private link to check again later; it expires 24 hours after signup. Your ticket number is not a tracking credential.",
      ),
    ]),
  ])
}

fn status_guidance(
  status: String,
  visitor_instructions: Option(String),
) -> element_module.Element(message) {
  case status {
    "waiting" ->
      html.p([], [html.text("Please wait until staff call your ticket number.")])
    "called" -> {
      let instruction = case visitor_instructions {
        Some(value) ->
          case string.trim(value) {
            "" ->
              "Please go to the service desk and show staff your ticket number."
            trimmed -> trimmed
          }
        _ -> "Please go to the service desk and show staff your ticket number."
      }
      html.div(
        [
          attr.class("called-ticket-next-step"),
          attr.attribute("role", "alert"),
          attr.attribute("aria-live", "assertive"),
        ],
        [
          html.strong([], [html.text("What to do next")]),
          html.p([], [html.text(instruction)]),
        ],
      )
    }
    "serving" ->
      html.p([attr.class("ticket-next-step")], [
        html.text(
          "Staff have started serving your ticket. Please follow their instructions.",
        ),
      ])
    "no_show" ->
      html.p([attr.class("ticket-next-step")], [
        html.text(
          "Your call was missed. Please speak with staff to find out what to do next.",
        ),
      ])
    "cancelled" ->
      html.p([attr.class("ticket-next-step")], [
        html.text("You left this queue. Staff will not call this ticket."),
      ])
    _ -> element_module.none()
  }
}

pub fn tracking_loading_page(
  notice: Option(String),
) -> element_module.Element(message) {
  html.section([attr.class("public-queue-card card ticket-tracking")], [
    html.h1([], [html.text("Loading your ticket")]),
    case notice {
      Some(message) ->
        html.p([attr.attribute("role", "status")], [html.text(message)])
      None -> html.p([], [html.text("Checking your private tracking link…")])
    },
  ])
}

fn ticket_status_label(status: String) -> String {
  case status {
    "waiting" -> "Waiting"
    "called" -> "Your number was called"
    "serving" -> "In service"
    "completed" -> "Service complete"
    "cancelled" -> "Cancelled"
    "no_show" -> "Marked as a no-show"
    _ -> "Ticket status unavailable"
  }
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

/// Render the public service choices for a location. Unavailable queues remain
/// visible with their state but cannot be selected.
pub fn service_selection_page(
  organization: String,
  location: String,
  services: List(#(String, String, String, Availability, Int)),
  navigate: fn(router.Route) -> message,
) -> element_module.Element(message) {
  html.section([attr.class("public-queue-card card service-selection")], [
    html.p([attr.class("public-organization")], [html.text(organization)]),
    html.h1([], [html.text("Choose a queue")]),
    html.p([attr.class("public-location")], [html.text(location)]),
    html.p([], [html.text("Choose an available queue to continue.")]),
    html.div(
      [attr.class("public-service-options")],
      list.map(services, fn(service) {
        let #(name, queue_name, public_id, availability, waiting_count) =
          service
        html.article([attr.class("public-service-option")], [
          html.div([], [
            html.h2([], [html.text(name)]),
            html.p([], [html.text(queue_name)]),
            html.p([attr.class("muted")], [
              html.text(case availability {
                Open -> "Open · " <> int.to_string(waiting_count) <> " waiting"
                _ -> title(availability)
              }),
            ]),
          ]),
          html.button(
            [
              attr.class("primary"),
              attr.disabled(!join_enabled(availability)),
              event.on_click(navigate(router.PublicQueue(public_id))),
            ],
            [
              html.text(case join_enabled(availability) {
                True -> "Choose queue"
                False -> "Unavailable"
              }),
            ],
          ),
        ])
      }),
    ),
  ])
}

import gleam/list
import gleam/option.{type Option, Some}
import lustre/attribute as attr
import lustre/element.{type Element, none}
import lustre/element/html
import lustre/event
import shared.{
  type LocationOverview, type OrganizationOverview, type ServiceOverview,
}

/// Render a role-aware organization summary. The component has no management
/// actions; it only describes next steps that are appropriate to the member.
pub fn overview_card(
  overview: OrganizationOverview,
  name: String,
  error: Option(String),
  on_name_input: fn(String) -> message,
  on_update: message,
) -> Element(message) {
  html.section([attr.class("card setup-card organization-overview")], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [
          html.text(case overview.can_manage {
            True -> "Administrator"
            False -> "Operator access"
          }),
        ]),
        html.h2([], [html.text(overview.organization.name)]),
        case overview.can_manage {
          True ->
            html.form(
              [
                attr.class("organization-name-form"),
                event.on_submit(fn(_) { on_update }),
              ],
              [
                html.label([attr.class("field")], [
                  html.text("Organization name"),
                  html.input([
                    attr.attribute("aria-label", "Organization name"),
                    attr.attribute("value", case name == "" {
                      True -> overview.organization.name
                      _ -> name
                    }),
                    attr.required(True),
                    event.on_input(on_name_input),
                  ]),
                ]),
                html.button(
                  [attr.class("secondary"), attr.attribute("type", "submit")],
                  [html.text("Save name")],
                ),
                case error {
                  Some(message) ->
                    html.p(
                      [
                        attr.class("sign-in-error"),
                        attr.attribute("role", "alert"),
                      ],
                      [html.text(message)],
                    )
                  _ -> none()
                },
              ],
            )
          False -> none()
        },
      ]),
    ]),
    case overview.locations {
      [] ->
        html.div([attr.class("empty-state")], [
          html.h3([], [
            html.text(case overview.can_manage {
              True -> "Start by creating a location"
              False -> "No locations assigned"
            }),
          ]),
          html.p([], [
            html.text(case overview.can_manage {
              True ->
                "Create your first location, then add its services and queues."
              False -> "Ask an administrator to grant you access to a location."
            }),
          ]),
        ])
      locations ->
        html.div(
          [attr.class("location-list")],
          list.map(locations, fn(location) {
            location_card(overview.can_manage, location)
          }),
        )
    },
  ])
}

fn location_card(
  can_manage: Bool,
  location: LocationOverview,
) -> Element(message) {
  html.article([attr.class("location-card")], [
    html.div([attr.class("location-heading")], [
      html.div([], [
        html.h3([], [html.text(location.location.name)]),
        html.p([], [html.text(location.location.timezone)]),
      ]),
      html.span(
        [
          attr.class(case location.location.is_active {
            True -> "status active"
            False -> "status inactive"
          }),
        ],
        [
          html.text(case location.location.is_active {
            True -> "Active"
            False -> "Inactive"
          }),
        ],
      ),
    ]),
    case location.services {
      [] ->
        html.div([attr.class("empty-state")], [
          html.p([], [
            html.text(case can_manage {
              True ->
                "No services yet. Add a service here, then configure a queue."
              False -> "No services are configured at this location yet."
            }),
          ]),
        ])
      services ->
        html.div([attr.class("service-list")], list.map(services, service_card))
    },
  ])
}

fn service_card(service: ServiceOverview) -> Element(message) {
  html.div([attr.class("service-row")], [
    html.div([], [
      html.strong([], [html.text(service.service.name)]),
      html.p([], [
        html.text(case service.service.is_active {
          True -> "Active service"
          False -> "Inactive service"
        }),
      ]),
    ]),
    case service.queues {
      [] -> html.p([attr.class("muted")], [html.text("No queues configured")])
      queues ->
        html.div(
          [attr.class("queue-tags")],
          list.map(queues, fn(queue) {
            html.span([attr.class("queue-tag")], [html.text(queue.name)])
          }),
        )
    },
  ])
}

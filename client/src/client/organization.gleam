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
  type LocationOverview, type OrganizationOverview, type Queue,
  type ServiceOverview, Anonymous, Closed, NameRequired, Open, Paused,
}
import shared/json as shared_json

pub type Model {
  Model(
    name: String,
    error: Option(String),
    location_organization_id: Option(String),
    location_id: Option(String),
    location_name: String,
    timezone: String,
    location_form: Bool,
    location_error: Option(String),
    service_location_id: Option(String),
    service_id: Option(String),
    service_name: String,
    service_description: String,
    service_form: Bool,
    service_error: Option(String),
  )
}

pub type Message {
  NameChanged(String)
  Submit(String, String)
  Updated(Result(OrganizationOverview, rsvp.Error(String)))
  NewLocation(String)
  EditLocation(String, String, String, String)
  LocationNameChanged(String)
  TimezoneChanged(String)
  SaveLocation(String)
  CancelLocation
  LocationSaved(Result(OrganizationOverview, rsvp.Error(String)))
  NewService(String)
  EditService(String, String, String, String)
  ServiceNameChanged(String)
  ServiceDescriptionChanged(String)
  SaveService(String, String)
  CancelService
  ServiceSaved(Result(OrganizationOverview, rsvp.Error(String)))
  CreateQueue
}

pub fn init() -> Model {
  Model(
    name: "",
    error: None,
    location_organization_id: None,
    location_id: None,
    location_name: "",
    timezone: "UTC",
    location_form: False,
    location_error: None,
    service_location_id: None,
    service_id: None,
    service_name: "",
    service_description: "",
    service_form: False,
    service_error: None,
  )
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    NameChanged(name) -> #(Model(..model, name:, error: None), effect.none())
    Submit(organization_id, displayed_name) ->
      submit(model, organization_id, displayed_name)
    Updated(Ok(_)) -> #(Model(..model, name: "", error: None), effect.none())
    Updated(Error(_)) -> #(
      Model(
        ..model,
        error: Some("We couldn't update the organization name. Try again."),
      ),
      effect.none(),
    )
    NewLocation(organization_id) -> #(
      Model(
        ..model,
        location_organization_id: Some(organization_id),
        location_id: None,
        location_name: "",
        timezone: "America/Los_Angeles",
        location_form: True,
        location_error: None,
      ),
      effect.none(),
    )
    EditLocation(organization_id, id, name, timezone) -> #(
      Model(
        ..model,
        location_organization_id: Some(organization_id),
        location_id: Some(id),
        location_name: name,
        timezone: supported_timezone_or_blank(timezone),
        location_form: True,
        location_error: None,
      ),
      effect.none(),
    )
    LocationNameChanged(location_name) -> #(
      Model(..model, location_name:, location_error: None),
      effect.none(),
    )
    TimezoneChanged(timezone) -> #(
      Model(..model, timezone:, location_error: None),
      effect.none(),
    )
    SaveLocation(organization_id) -> save_location(model, organization_id)
    CancelLocation -> #(
      Model(
        ..model,
        location_organization_id: None,
        location_id: None,
        location_name: "",
        timezone: "America/Los_Angeles",
        location_form: False,
        location_error: None,
      ),
      effect.none(),
    )
    LocationSaved(Ok(_)) -> #(
      Model(
        ..model,
        location_organization_id: None,
        location_id: None,
        location_name: "",
        timezone: "America/Los_Angeles",
        location_form: False,
        location_error: None,
      ),
      effect.none(),
    )
    LocationSaved(Error(_)) -> #(
      Model(
        ..model,
        location_error: Some(
          "We couldn't save the location. Check the name and timezone.",
        ),
      ),
      effect.none(),
    )
    NewService(location_id) -> #(
      Model(
        ..model,
        service_location_id: Some(location_id),
        service_id: None,
        service_name: "",
        service_description: "",
        service_form: True,
        service_error: None,
      ),
      effect.none(),
    )
    EditService(location_id, id, name, description) -> #(
      Model(
        ..model,
        service_location_id: Some(location_id),
        service_id: Some(id),
        service_name: name,
        service_description: description,
        service_form: True,
        service_error: None,
      ),
      effect.none(),
    )
    ServiceNameChanged(service_name) -> #(
      Model(..model, service_name:, service_error: None),
      effect.none(),
    )
    ServiceDescriptionChanged(service_description) -> #(
      Model(..model, service_description:, service_error: None),
      effect.none(),
    )
    SaveService(organization_id, location_id) ->
      save_service(model, organization_id, location_id)
    CancelService -> #(
      Model(
        ..model,
        service_location_id: None,
        service_id: None,
        service_name: "",
        service_description: "",
        service_form: False,
        service_error: None,
      ),
      effect.none(),
    )
    ServiceSaved(Ok(_)) -> #(
      Model(
        ..model,
        service_location_id: None,
        service_id: None,
        service_name: "",
        service_description: "",
        service_form: False,
        service_error: None,
      ),
      effect.none(),
    )
    ServiceSaved(Error(_)) -> #(
      Model(
        ..model,
        service_error: Some(
          "We couldn't save the service. Check its name and try again.",
        ),
      ),
      effect.none(),
    )
    CreateQueue -> #(model, effect.none())
  }
}

fn supported_timezone_or_blank(timezone: String) -> String {
  case timezone {
    "America/Los_Angeles" | "US/Mountain" -> timezone
    _ -> ""
  }
}

fn save_location(
  model: Model,
  organization_id: String,
) -> #(Model, Effect(Message)) {
  case string.trim(model.location_name), string.trim(model.timezone) {
    "", _ -> #(
      Model(..model, location_error: Some("Enter a location name.")),
      effect.none(),
    )
    _, "" -> #(
      Model(..model, location_error: Some("Enter a timezone.")),
      effect.none(),
    )
    name, timezone -> {
      let body =
        json.object([
          #("name", json.string(name)),
          #("timezone", json.string(timezone)),
        ])
      let request = case model.location_id {
        Some(location_id) ->
          rsvp.put(
            "/api/organizations/"
              <> organization_id
              <> "/locations/"
              <> location_id,
            body,
            rsvp.expect_json(
              shared_json.organization_overview_decoder(),
              LocationSaved,
            ),
          )
        None ->
          rsvp.post(
            "/api/organizations/" <> organization_id <> "/locations",
            body,
            rsvp.expect_json(
              shared_json.organization_overview_decoder(),
              LocationSaved,
            ),
          )
      }
      #(Model(..model, location_error: None), request)
    }
  }
}

fn submit(
  model: Model,
  organization_id: String,
  displayed_name: String,
) -> #(Model, Effect(Message)) {
  let name = case model.name {
    "" -> displayed_name
    value -> value
  }
  case string.trim(name) {
    "" -> #(
      Model(..model, error: Some("Enter an organization name.")),
      effect.none(),
    )
    name -> #(
      Model(..model, error: None),
      rsvp.put(
        "/api/organizations/" <> organization_id,
        json.object([#("name", json.string(name))]),
        rsvp.expect_json(shared_json.organization_overview_decoder(), Updated),
      ),
    )
  }
}

fn save_service(
  model: Model,
  organization_id: String,
  location_id: String,
) -> #(Model, Effect(Message)) {
  let name = string.trim(model.service_name)
  case name {
    "" -> #(
      Model(..model, service_error: Some("Enter a service name.")),
      effect.none(),
    )
    _ -> {
      let body =
        json.object([
          #("name", json.string(name)),
          #(
            "description",
            json.nullable(
              case string.trim(model.service_description) {
                "" -> None
                value -> Some(value)
              },
              json.string,
            ),
          ),
        ])
      let path =
        "/api/organizations/"
        <> organization_id
        <> "/locations/"
        <> location_id
        <> "/services"
      let request = case model.service_id {
        Some(id) ->
          rsvp.put(
            path <> "/" <> id,
            body,
            rsvp.expect_json(
              shared_json.organization_overview_decoder(),
              ServiceSaved,
            ),
          )
        None ->
          rsvp.post(
            path,
            body,
            rsvp.expect_json(
              shared_json.organization_overview_decoder(),
              ServiceSaved,
            ),
          )
      }
      #(Model(..model, service_error: None), request)
    }
  }
}

/// Render a role-aware organization summary. The component has no management
/// actions; it only describes next steps that are appropriate to the member.
pub fn overview_card(
  overview: OrganizationOverview,
  editor: Model,
  lift: fn(Message) -> message,
) -> Element(message) {
  html.section([attr.class("card setup-card organization-overview")], [
    html.div([attr.class("organization-overview-content")], [
      html.div([attr.class("organization-profile-column")], [
        html.div([attr.class("page-heading")], [
          html.div([], [
            html.p([attr.class("eyebrow")], [
              html.text(case overview.can_manage {
                True -> "Administrator"
                False -> "Operator access"
              }),
            ]),

            case overview.can_manage {
              True ->
                html.form(
                  [
                    attr.class("organization-name-form"),
                    event.on_submit(fn(_) {
                      lift(
                        Submit(
                          overview.organization.id,
                          case editor.name == "" {
                            True -> overview.organization.name
                            False -> editor.name
                          },
                        ),
                      )
                    }),
                  ],
                  [
                    html.label([attr.class("field")], [
                      html.text("Organization name"),
                      html.input([
                        attr.attribute("aria-label", "Organization name"),
                        attr.attribute("value", case editor.name == "" {
                          True -> overview.organization.name
                          _ -> editor.name
                        }),
                        attr.required(True),
                        event.on_input(fn(value) { lift(NameChanged(value)) }),
                      ]),
                    ]),
                    html.button(
                      [
                        attr.class("secondary"),
                        attr.attribute("type", "submit"),
                      ],
                      [html.text("Save name")],
                    ),
                    case editor.error {
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
            case overview.can_manage {
              True ->
                html.button(
                  [
                    attr.class("secondary"),
                    attr.attribute("type", "button"),
                    event.on_click(lift(NewLocation(overview.organization.id))),
                  ],
                  [html.text("Add location")],
                )
              False -> none()
            },
          ]),
        ]),
      ]),
      html.div([attr.class("organization-locations-column")], [
        html.h2([], [html.text("Locations")]),
        case overview.can_manage {
          True if overview.locations == [] && !editor.location_form ->
            html.button(
              [
                attr.class("secondary"),
                attr.attribute("type", "button"),
                event.on_click(lift(NewLocation(overview.organization.id))),
              ],
              [html.text("Add location")],
            )
          _ -> none()
        },
        case
          editor.location_organization_id,
          editor.location_form,
          editor.location_id,
          overview.locations
        {
          Some(organization_id), True, None, []
            if organization_id == overview.organization.id
          -> location_editor(editor, lift, overview.organization.id)
          _, _, _, _ -> none()
        },
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
                  False ->
                    "Ask an administrator to grant you access to a location."
                }),
              ]),
            ])
          locations ->
            html.div(
              [attr.class("location-list")],
              list.map(locations, fn(location) {
                location_card(
                  overview.can_manage,
                  location,
                  editor,
                  lift,
                  overview.organization.id,
                )
              }),
            )
        },
      ]),
    ]),
  ])
}

fn location_editor(
  model: Model,
  lift: fn(Message) -> message,
  organization_id: String,
) -> Element(message) {
  html.form(
    [
      attr.class("location-form"),
      event.on_submit(fn(_) { lift(SaveLocation(organization_id)) }),
    ],
    [
      html.label([attr.class("field")], [
        html.text("Location name"),
        html.input([
          attr.attribute("aria-label", "Location name"),
          attr.attribute("value", model.location_name),
          attr.required(True),
          event.on_input(fn(value) { lift(LocationNameChanged(value)) }),
        ]),
      ]),
      html.label([attr.class("field")], [
        html.text("Timezone"),
        html.select(
          [
            attr.attribute("aria-label", "Timezone"),
            attr.required(True),
            event.on_input(fn(value) { lift(TimezoneChanged(value)) }),
          ],
          [
            html.option(
              [
                attr.attribute("value", ""),
                attr.selected(model.timezone == ""),
                attr.disabled(True),
              ],
              "Select timezone",
            ),
            html.option(
              [
                attr.attribute("value", "America/Los_Angeles"),
                attr.selected(model.timezone == "America/Los_Angeles"),
              ],
              "America/Los_Angeles",
            ),
            html.option(
              [
                attr.attribute("value", "US/Mountain"),
                attr.selected(model.timezone == "US/Mountain"),
              ],
              "US/Mountain",
            ),
          ],
        ),
      ]),
      html.div([attr.class("location-form-actions")], [
        html.button(
          [
            attr.class("quiet"),
            attr.attribute("type", "button"),
            event.on_click(lift(CancelLocation)),
          ],
          [html.text("Cancel")],
        ),
        html.button([attr.class("primary"), attr.attribute("type", "submit")], [
          html.text("Save location"),
        ]),
      ]),
      case model.location_error {
        Some(message) ->
          html.p(
            [attr.class("sign-in-error"), attr.attribute("role", "alert")],
            [html.text(message)],
          )
        _ -> none()
      },
    ],
  )
}

fn location_card(
  can_manage: Bool,
  location: LocationOverview,
  editor: Model,
  lift: fn(Message) -> message,
  organization_id: String,
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
      case can_manage {
        True ->
          html.button(
            [
              attr.class("secondary"),
              attr.attribute("type", "button"),
              event.on_click(
                lift(EditLocation(
                  organization_id,
                  location.location.id,
                  location.location.name,
                  location.location.timezone,
                )),
              ),
            ],
            [html.text("Edit location")],
          )
        False -> none()
      },
    ]),
    case
      editor.location_organization_id,
      editor.location_form,
      editor.location_id
    {
      Some(edited_organization_id), True, Some(id)
        if edited_organization_id == organization_id
        && id == location.location.id
      -> location_editor(editor, lift, organization_id)
      _, _, _ -> none()
    },
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
          case can_manage {
            True ->
              html.button(
                [
                  attr.class("secondary"),
                  attr.attribute("type", "button"),
                  event.on_click(lift(NewService(location.location.id))),
                ],
                [html.text("Add service")],
              )
            False -> none()
          },
        ])
      services ->
        html.div([attr.class("service-list")], [
          case can_manage {
            True ->
              html.button(
                [
                  attr.class("secondary"),
                  attr.attribute("type", "button"),
                  event.on_click(lift(NewService(location.location.id))),
                ],
                [html.text("Add service")],
              )
            False -> none()
          },
          ..list.map(services, fn(service) {
            service_card(can_manage, service, location.location.id, lift)
          })
        ])
    },
    case editor.service_location_id, editor.service_form {
      Some(id), True if id == location.location.id ->
        service_editor(editor, lift, organization_id, location.location.id)
      _, _ -> none()
    },
  ])
}

fn service_card(
  can_manage: Bool,
  service: ServiceOverview,
  location_id: String,
  lift: fn(Message) -> message,
) -> Element(message) {
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
      [] ->
        html.div([attr.class("queue-empty-state")], [
          html.p([attr.class("muted")], [html.text("No queues configured")]),
          case can_manage {
            True ->
              html.button(
                [
                  attr.class("quiet"),
                  attr.attribute("type", "button"),
                  event.on_click(lift(CreateQueue)),
                ],
                [html.text("Set up a queue")],
              )
            False -> none()
          },
        ])
      queues ->
        html.div(
          [attr.class("queue-overview-list")],
          list.map(queues, queue_overview),
        )
    },
    case can_manage {
      True ->
        html.button(
          [
            attr.class("quiet"),
            attr.attribute("type", "button"),
            event.on_click(
              lift(
                EditService(
                  location_id,
                  service.service.id,
                  service.service.name,
                  case service.service.description {
                    Some(description) -> description
                    None -> ""
                  },
                ),
              ),
            ),
          ],
          [html.text("Edit")],
        )
      False -> none()
    },
  ])
}

fn queue_overview(queue: Queue) -> Element(message) {
  html.div([attr.class("queue-overview")], [
    html.strong([], [html.text(queue.name)]),
    html.div([attr.class("queue-overview-statuses")], [
      html.span(
        [
          attr.class(case queue.is_active {
            True -> "status active"
            False -> "status inactive"
          }),
        ],
        [
          html.text(case queue.is_active {
            True -> "Active"
            False -> "Inactive"
          }),
        ],
      ),
      html.span([attr.class("status")], [
        html.text(case queue.current_session_state {
          None -> "No session"
          Some(Open) -> "Open"
          Some(Paused) -> "Paused"
          Some(Closed) -> "Closed"
        }),
      ]),
    ]),
    html.p([attr.class("queue-configuration")], [
      html.text(case queue.identity_policy {
        Anonymous -> "Anonymous"
        NameRequired -> "Name required"
      }),
      html.text(" · "),
      html.text(case queue.active_ticket_capacity {
        None -> "Unlimited capacity"
        Some(capacity) -> "Capacity " <> int.to_string(capacity)
      }),
    ]),
  ])
}

fn service_editor(
  model: Model,
  lift: fn(Message) -> message,
  organization_id: String,
  location_id: String,
) -> Element(message) {
  html.form(
    [
      attr.class("service-form"),
      event.on_submit(fn(_) { lift(SaveService(organization_id, location_id)) }),
    ],
    [
      html.label([attr.class("field")], [
        html.text("Service name"),
        html.input([
          attr.attribute("value", model.service_name),
          attr.attribute("aria-label", "Service name"),
          attr.required(True),
          event.on_input(fn(value) { lift(ServiceNameChanged(value)) }),
        ]),
      ]),
      html.label([attr.class("field")], [
        html.text("Description (optional)"),
        html.input([
          attr.attribute("value", model.service_description),
          attr.attribute("aria-label", "Service description"),
          event.on_input(fn(value) { lift(ServiceDescriptionChanged(value)) }),
        ]),
      ]),
      html.div([attr.class("location-form-actions")], [
        html.button(
          [
            attr.class("quiet"),
            attr.attribute("type", "button"),
            event.on_click(lift(CancelService)),
          ],
          [html.text("Cancel")],
        ),
        html.button([attr.class("primary"), attr.attribute("type", "submit")], [
          html.text("Save service"),
        ]),
      ]),
      case model.service_error {
        Some(message) ->
          html.p(
            [attr.class("sign-in-error"), attr.attribute("role", "alert")],
            [html.text(message)],
          )
        None -> none()
      },
    ],
  )
}

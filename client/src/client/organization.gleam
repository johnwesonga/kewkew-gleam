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
    name: String,
    error: Option(String),
    location_organization_id: Option(String),
    location_id: Option(String),
    location_name: String,
    timezone: String,
    location_form: Bool,
    location_error: Option(String),
  )
}

pub type Message {
  NameChanged(String)
  Submit(String)
  Updated(Result(OrganizationOverview, rsvp.Error(String)))
  NewLocation(String)
  EditLocation(String, String, String, String)
  LocationNameChanged(String)
  TimezoneChanged(String)
  SaveLocation(String)
  CancelLocation
  LocationSaved(Result(OrganizationOverview, rsvp.Error(String)))
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
  )
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    NameChanged(name) -> #(Model(..model, name:, error: None), effect.none())
    Submit(organization_id) -> submit(model, organization_id)
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

fn submit(model: Model, organization_id: String) -> #(Model, Effect(Message)) {
  case string.trim(model.name) {
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

/// Render a role-aware organization summary. The component has no management
/// actions; it only describes next steps that are appropriate to the member.
pub fn overview_card(
  overview: OrganizationOverview,
  editor: Model,
  lift: fn(Message) -> message,
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

        case overview.can_manage {
          True ->
            html.form(
              [
                attr.class("organization-name-form"),
                event.on_submit(fn(_) { lift(Submit(overview.organization.id)) }),
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
                  [attr.class("secondary"), attr.attribute("type", "submit")],
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
            case
              editor.location_organization_id == Some(overview.organization.id),
              editor.location_form
            {
              True, True ->
                location_editor(editor, lift, overview.organization.id)
              False, False ->
                html.button(
                  [
                    attr.class("secondary"),
                    attr.attribute("type", "button"),
                    event.on_click(lift(NewLocation(overview.organization.id))),
                  ],
                  [html.text("Add location")],
                )
              _, _ -> none()
            }
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

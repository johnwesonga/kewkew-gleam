import gleam/bit_array
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element, none}
import lustre/element/html
import lustre/event
import plinth/browser/clipboard
import qrkit
import qrkit/render/svg
import rsvp
import shared.{
  type LocationOverview, type OrganizationOverview, type Queue,
  type ServiceOverview, Anonymous, Closed, NameRequired, Open, Paused,
}
import shared/json as shared_json

pub type Model {
  Model(
    organization_id: String,
    location_id: String,
    service_id: String,
    queue_id: Option(String),
    origin: String,
    name: String,
    identity_policy: String,
    capacity: String,
    error: Option(String),
    copy_status: Option(String),
  )
}

pub type Message {
  Begin(String, String, String)
  BeginEdit(String, String, String, Queue)
  OrganizationChanged(String)
  LocationChanged(String)
  ServiceChanged(String)
  NameChanged(String)
  IdentityPolicyChanged(String)
  CapacityChanged(String)
  Save
  Cancel
  BackToList
  Created(Result(OrganizationOverview, rsvp.Error(String)))
  Updated(Result(OrganizationOverview, rsvp.Error(String)))
  CopyLink(String)
  LinkCopied(Result(Nil, String))
}

pub fn init() -> Model {
  Model("", "", "", None, "", "", "anonymous", "", None, None)
}

pub fn set_origin(model: Model, origin: String) -> Model {
  Model(..model, origin:)
}

pub fn begin(
  model: Model,
  org_id: String,
  loc_id: String,
  service_id: String,
) -> Model {
  Model(
    organization_id: org_id,
    location_id: loc_id,
    service_id:,
    queue_id: None,
    origin: model.origin,
    name: "",
    identity_policy: "anonymous",
    capacity: "",
    error: None,
    copy_status: None,
  )
}

pub fn begin_edit(
  model: Model,
  org_id: String,
  loc_id: String,
  service_id: String,
  queue: Queue,
) -> Model {
  Model(
    organization_id: org_id,
    location_id: loc_id,
    service_id:,
    queue_id: Some(queue.id),
    origin: model.origin,
    name: queue.name,
    identity_policy: case queue.identity_policy {
      Anonymous -> "anonymous"
      NameRequired -> "name_required"
    },
    capacity: case queue.active_ticket_capacity {
      Some(value) -> int.to_string(value)
      None -> ""
    },
    error: None,
    copy_status: None,
  )
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    Begin(org_id, loc_id, service_id) -> #(
      begin(model, org_id, loc_id, service_id),
      effect.none(),
    )
    BeginEdit(org_id, loc_id, service_id, queue) -> #(
      begin_edit(model, org_id, loc_id, service_id, queue),
      effect.none(),
    )
    CopyLink(url) -> #(
      model,
      effect.from(fn(dispatch) {
        let _ =
          clipboard.write_text(url)
          |> promise.map(fn(result) {
            dispatch(LinkCopied(result))
            Nil
          })
        Nil
      }),
    )
    LinkCopied(Ok(Nil)) -> #(
      Model(..model, copy_status: Some("Public queue link copied.")),
      effect.none(),
    )
    LinkCopied(Error(_)) -> #(
      Model(
        ..model,
        copy_status: Some("Copy failed. Select and copy the link."),
      ),
      effect.none(),
    )
    OrganizationChanged(organization_id) -> #(
      Model(
        ..model,
        organization_id:,
        location_id: "",
        service_id: "",
        error: None,
        copy_status: None,
      ),
      effect.none(),
    )
    LocationChanged(location_id) -> #(
      Model(..model, location_id:, service_id: "", error: None),
      effect.none(),
    )
    ServiceChanged(service_id) -> #(
      Model(..model, service_id:, error: None),
      effect.none(),
    )
    NameChanged(name) -> #(Model(..model, name:, error: None), effect.none())
    IdentityPolicyChanged(identity_policy) -> #(
      Model(..model, identity_policy:, error: None),
      effect.none(),
    )
    CapacityChanged(capacity) -> #(
      Model(..model, capacity:, error: None),
      effect.none(),
    )
    Save -> save(model)
    Cancel -> #(init(), effect.none())
    BackToList -> #(init(), effect.none())
    Created(Ok(_)) -> #(init(), effect.none())
    Updated(Ok(_)) -> #(init(), effect.none())
    Created(Error(_)) -> #(
      Model(
        ..model,
        error: Some(
          "We couldn't create the queue. Check the settings and try again.",
        ),
      ),
      effect.none(),
    )
    Updated(Error(_)) -> #(
      Model(
        ..model,
        error: Some(
          "We couldn't update the queue. Check the settings and try again.",
        ),
      ),
      effect.none(),
    )
  }
}

pub fn overview_from_message(message: Message) -> Option(OrganizationOverview) {
  case message {
    Created(Ok(overview)) | Updated(Ok(overview)) -> Some(overview)
    _ -> None
  }
}

fn save(model: Model) -> #(Model, Effect(Message)) {
  let name = string.trim(model.name)
  let capacity = case string.trim(model.capacity) {
    "" -> Ok(None)
    value ->
      case int.parse(value) {
        Ok(number) if number > 0 -> Ok(Some(number))
        _ -> Error(Nil)
      }
  }
  case
    name,
    model.organization_id,
    model.location_id,
    model.service_id,
    capacity
  {
    "", _, _, _, _ -> validation_error(model, "Enter a queue name.")
    _, "", _, _, _ -> validation_error(model, "Choose an organization.")
    _, _, "", _, _ -> validation_error(model, "Choose a location.")
    _, _, _, "", _ -> validation_error(model, "Choose a service.")
    _, _, _, _, Error(_) ->
      validation_error(model, "Capacity must be a positive whole number.")
    _, org_id, loc_id, service_id, Ok(capacity) -> {
      let body =
        json.object([
          #("name", json.string(name)),
          #("identity_policy", json.string(model.identity_policy)),
          #("active_ticket_capacity", json.nullable(capacity, json.int)),
        ])
      let path =
        "/api/organizations/"
        <> org_id
        <> "/locations/"
        <> loc_id
        <> "/services/"
        <> service_id
        <> "/queues"
      let request = case model.queue_id {
        Some(queue_id) ->
          rsvp.put(
            path <> "/" <> queue_id,
            body,
            rsvp.expect_json(
              shared_json.organization_overview_decoder(),
              Updated,
            ),
          )
        None ->
          rsvp.post(
            path,
            body,
            rsvp.expect_json(
              shared_json.organization_overview_decoder(),
              Created,
            ),
          )
      }
      #(model, request)
    }
  }
}

fn validation_error(
  model: Model,
  message: String,
) -> #(Model, Effect(Message)) {
  #(Model(..model, error: Some(message)), effect.none())
}

pub fn view(
  model: Model,
  overviews: Option(List(OrganizationOverview)),
  lift: fn(Message) -> message,
) -> Element(message) {
  let organizations = case overviews {
    Some(values) -> list.filter(values, fn(value) { value.can_manage })
    None -> []
  }
  case organizations {
    [] ->
      html.section([attr.class("card setup-card")], [
        html.div([attr.class("empty-state")], [
          html.h3([], [html.text("Administrator access required")]),
          html.p([], [
            html.text("Only organization administrators can create queues."),
          ]),
        ]),
      ])
    _ ->
      case model.queue_id {
        Some(queue_id) -> edit_queue_view(model, queue_id, organizations, lift)
        None ->
          html.section([], [
            existing_queues(organizations, lift),
            queue_form(model, organizations, lift),
          ])
      }
  }
}

fn edit_queue_view(
  model: Model,
  queue_id: String,
  organizations: List(OrganizationOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  case find_queue_context(organizations, queue_id) {
    None ->
      html.section([attr.class("page card not-found-card")], [
        html.h1([], [html.text("Queue unavailable")]),
        html.p([], [html.text("This queue is no longer available to edit.")]),
        html.button(
          [
            attr.class("secondary"),
            attr.attribute("type", "button"),
            event.on_click(lift(BackToList)),
          ],
          [html.text("Back to queue settings")],
        ),
      ])
    Some(#(organization_name, location_name, service_name, queue)) ->
      html.section([attr.class("queue-edit-page")], [
        html.button(
          [
            attr.class("quiet queue-back-button"),
            attr.attribute("type", "button"),
            event.on_click(lift(BackToList)),
          ],
          [html.text("← Back to queue settings")],
        ),
        html.div([attr.class("page-heading queue-edit-heading")], [
          html.div([], [
            html.h1([], [html.text("Queue configuration")]),
            html.p([attr.class("subhead")], [
              html.text(
                "Update visitor rules or configure a manual session for "
                <> queue.name
                <> ".",
              ),
            ]),
          ]),
        ]),
        html.section([attr.class("queue-edit-card card")], [
          html.h2([], [html.text("Queue details")]),
          html.p([attr.class("muted queue-fixed-copy")], [
            html.text("Location and service are fixed after creation."),
          ]),
          html.div([attr.class("queue-fixed-details")], [
            html.div([], [
              html.strong([], [html.text("Location")]),
              html.p([], [html.text(location_name)]),
            ]),
            html.div([], [
              html.strong([], [html.text("Service")]),
              html.p([], [html.text(service_name)]),
            ]),
          ]),
          html.div([attr.class("queue-detail-meta")], [
            html.span([attr.class("status")], [
              html.text(case queue.is_active {
                True -> "Queue active"
                False -> "Queue inactive"
              }),
            ]),
            html.span([attr.class("status")], [
              html.text(case queue.current_session_state {
                None -> "No session"
                Some(Open) -> "Session open"
                Some(Paused) -> "Session paused"
                Some(Closed) -> "Session closed"
              }),
            ]),
          ]),
          html.form(
            [
              attr.class("queue-edit-form"),
              event.on_submit(fn(_) { lift(Save) }),
            ],
            [
              html.label([attr.class("field")], [
                html.text("Queue name"),
                html.input([
                  attr.attribute("value", model.name),
                  attr.attribute("aria-label", "Queue name"),
                  attr.required(True),
                  event.on_input(fn(value) { lift(NameChanged(value)) }),
                ]),
              ]),
              html.label([attr.class("field")], [
                html.text("Visitor identity"),
                html.select(
                  [
                    attr.attribute("aria-label", "Visitor identity"),
                    attr.required(True),
                    event.on_input(fn(value) {
                      lift(IdentityPolicyChanged(value))
                    }),
                  ],
                  [
                    html.option(
                      [
                        attr.attribute("value", "anonymous"),
                        attr.selected(model.identity_policy == "anonymous"),
                      ],
                      "Anonymous tickets",
                    ),
                    html.option(
                      [
                        attr.attribute("value", "name_required"),
                        attr.selected(model.identity_policy == "name_required"),
                      ],
                      "First and last name required",
                    ),
                  ],
                ),
                html.p([attr.class("muted")], [
                  html.text(
                    "Changes apply to future joins. Existing tickets remain unchanged.",
                  ),
                ]),
              ]),
              html.label([attr.class("field")], [
                html.text("Active ticket capacity"),
                html.small([], [
                  html.text("Optional; leave blank for unlimited"),
                ]),
                html.input([
                  attr.attribute("type", "number"),
                  attr.attribute("min", "1"),
                  attr.attribute("step", "1"),
                  attr.attribute("value", model.capacity),
                  attr.attribute("aria-label", "Active ticket capacity"),
                  event.on_input(fn(value) { lift(CapacityChanged(value)) }),
                ]),
                html.p([attr.class("muted")], [
                  html.text(
                    "Lowering the limit will not cancel existing tickets.",
                  ),
                ]),
              ]),
              case model.error {
                Some(message) ->
                  html.p(
                    [
                      attr.class("sign-in-error"),
                      attr.attribute("role", "alert"),
                    ],
                    [html.text(message)],
                  )
                None -> none()
              },
              html.div([attr.class("queue-edit-actions")], [
                html.button(
                  [
                    attr.class("primary"),
                    attr.attribute("type", "submit"),
                  ],
                  [html.text("Save changes")],
                ),
                html.button(
                  [
                    attr.class("quiet"),
                    attr.attribute("type", "button"),
                    event.on_click(lift(BackToList)),
                  ],
                  [html.text("Cancel")],
                ),
              ]),
            ],
          ),
          html.hr([attr.class("queue-share-divider")]),
          html.h2([], [html.text("Public link and QR code")]),
          html.div([attr.class("queue-share-banner")], [
            html.text("Share link & QR"),
          ]),
          html.div([attr.class("queue-share-card")], [
            html.p([], [
              html.text("Reusable link for "),
              html.strong([], [html.text(queue.name)]),
            ]),
            case queue.public_id {
              Some(public_id) -> {
                let path = "/q/" <> public_id
                let url = public_url(model.origin, path)
                let code = qr_svg(url)
                html.div([attr.class("public-share-content")], [
                  html.div([attr.class("public-share-actions")], [
                    html.a(
                      [
                        attr.class("public-queue-url"),
                        attr.attribute("href", url),
                      ],
                      [html.text(url)],
                    ),
                    html.button(
                      [
                        attr.class("secondary"),
                        attr.attribute("type", "button"),
                        event.on_click(lift(CopyLink(url))),
                      ],
                      [html.text("Copy link")],
                    ),
                  ]),
                  case model.copy_status {
                    Some(status) ->
                      html.p(
                        [
                          attr.class("copy-link-status"),
                          attr.attribute("role", "status"),
                        ],
                        [html.text(status)],
                      )
                    None -> none()
                  },
                  case code {
                    Some(svg_markup) -> {
                      let download_url =
                        "data:image/svg+xml;base64,"
                        <> {
                          bit_array.from_string(svg_markup)
                          |> bit_array.base64_encode(False)
                        }
                      html.div([attr.class("queue-qr-result")], [
                        element.unsafe_raw_html(
                          "",
                          "div",
                          [
                            attr.class("queue-qr-code"),
                            attr.attribute("role", "img"),
                            attr.attribute("aria-label", "QR code for " <> url),
                          ],
                          svg_markup,
                        ),
                        html.a(
                          [
                            attr.class("secondary download-qr"),
                            attr.attribute("href", download_url),
                            attr.attribute(
                              "download",
                              "kewkew-queue-" <> public_id <> ".svg",
                            ),
                          ],
                          [html.text("Download QR code")],
                        ),
                      ])
                    }
                    None ->
                      html.p([attr.class("sign-in-error")], [
                        html.text(
                          "QR code could not be generated for this link.",
                        ),
                      ])
                  },
                ])
              }
              None ->
                html.p([attr.class("muted")], [
                  html.text("No public link is assigned to this queue."),
                ])
            },
          ]),
          html.small([attr.class("muted")], [html.text(organization_name)]),
        ]),
      ])
  }
}

fn find_queue_context(
  organizations: List(OrganizationOverview),
  queue_id: String,
) -> Option(#(String, String, String, Queue)) {
  let matches =
    list.flat_map(organizations, fn(organization) {
      list.flat_map(organization.locations, fn(location) {
        list.flat_map(location.services, fn(service) {
          service.queues
          |> list.filter(fn(queue) { queue.id == queue_id })
          |> list.map(fn(queue) {
            #(
              organization.organization.name,
              location.location.name,
              service.service.name,
              queue,
            )
          })
        })
      })
    })
  case matches {
    [context, ..] -> Some(context)
    [] -> None
  }
}

fn public_url(origin: String, path: String) -> String {
  case origin {
    "" -> path
    _ -> origin <> path
  }
}

fn qr_svg(url: String) -> Option(String) {
  case qrkit.encode(url) {
    Ok(code) -> Some(svg.to_string(code))
    Error(_) -> None
  }
}

fn existing_queues(
  organizations: List(OrganizationOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  let queues =
    list.flat_map(organizations, fn(organization) {
      list.flat_map(organization.locations, fn(location) {
        list.flat_map(location.services, fn(service) {
          list.map(service.queues, fn(queue) {
            queue_entry(
              organization.organization.id,
              location.location.id,
              service.service.id,
              organization.organization.name,
              location.location.name,
              service.service.name,
              queue,
              lift,
            )
          })
        })
      })
    })
  case queues {
    [] -> none()
    _ ->
      html.section([attr.class("existing-queues")], [
        html.div([attr.class("page-heading")], [
          html.div([], [
            html.p([attr.class("eyebrow")], [html.text("Queue settings")]),
            html.h2([], [html.text("Existing queues")]),
          ]),
        ]),
        html.div([attr.class("existing-queue-list")], queues),
      ])
  }
}

fn queue_entry(
  organization_id: String,
  location_id: String,
  service_id: String,
  organization_name: String,
  location_name: String,
  service_name: String,
  queue: Queue,
  lift: fn(Message) -> message,
) -> Element(message) {
  html.article([attr.class("existing-queue-card card")], [
    html.div([], [
      html.strong([], [html.text(queue.name)]),
      html.p([attr.class("muted")], [
        html.text(
          organization_name <> " · " <> location_name <> " · " <> service_name,
        ),
      ]),
      html.p([attr.class("queue-configuration")], [
        html.text(case queue.identity_policy {
          Anonymous -> "Anonymous"
          NameRequired -> "First and last name required"
        }),
        html.text(" · "),
        html.text(case queue.active_ticket_capacity {
          None -> "Unlimited capacity"
          Some(capacity) -> "Maximum " <> int.to_string(capacity) <> " active"
        }),
      ]),
    ]),
    html.button(
      [
        attr.class("secondary"),
        attr.attribute("type", "button"),
        event.on_click(
          lift(BeginEdit(organization_id, location_id, service_id, queue)),
        ),
      ],
      [html.text("Edit")],
    ),
  ])
}

fn queue_form(
  model: Model,
  organizations: List(OrganizationOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  let selected_org = find_organization(organizations, model.organization_id)
  let locations = case selected_org {
    Some(overview) -> overview.locations
    None -> []
  }
  let selected_location = find_location(locations, model.location_id)
  let services = case selected_location {
    Some(location) -> location.services
    None -> []
  }
  html.section([], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Queue configuration")]),
        html.h1([], [
          html.text(case model.queue_id {
            Some(_) -> "Edit queue configuration"
            None -> "Create a queue"
          }),
        ]),
        html.p([attr.class("subhead")], [
          html.text(
            "Set up a queue for a service. It will remain inactive until you enable it and open a session.",
          ),
        ]),
      ]),
    ]),
    html.div([attr.class("settings-layout")], [
      html.form(
        [
          attr.class("settings-card card queue-create-form"),
          event.on_submit(fn(_) { lift(Save) }),
        ],
        [
          html.label([attr.class("field")], [
            html.text("Queue name"),
            html.input([
              attr.attribute("value", model.name),
              attr.attribute("aria-label", "Queue name"),
              attr.required(True),
              event.on_input(fn(value) { lift(NameChanged(value)) }),
            ]),
          ]),
          case model.queue_id {
            Some(_) ->
              html.p([attr.class("muted queue-fixed-service")], [
                html.text("Location and service are fixed for this queue."),
              ])
            None ->
              html.div([attr.class("queue-create-selectors")], [
                organization_select(model, organizations, lift),
                location_select(model, locations, lift),
                service_select(model, services, lift),
              ])
          },
          html.label([attr.class("field")], [
            html.text("Visitor identity"),
            html.select(
              [
                attr.attribute("aria-label", "Visitor identity"),
                attr.required(True),
                event.on_input(fn(value) { lift(IdentityPolicyChanged(value)) }),
              ],
              [
                html.option(
                  [
                    attr.attribute("value", "anonymous"),
                    attr.selected(model.identity_policy == "anonymous"),
                  ],
                  "Anonymous ticket",
                ),
                html.option(
                  [
                    attr.attribute("value", "name_required"),
                    attr.selected(model.identity_policy == "name_required"),
                  ],
                  "First and last name required",
                ),
              ],
            ),
          ]),
          html.label([attr.class("field")], [
            html.text("Maximum active tickets (optional)"),
            html.input([
              attr.attribute("type", "number"),
              attr.attribute("min", "1"),
              attr.attribute("step", "1"),
              attr.attribute("value", model.capacity),
              attr.attribute("aria-label", "Maximum active tickets (optional)"),
              event.on_input(fn(value) { lift(CapacityChanged(value)) }),
            ]),
          ]),
          html.div([attr.class("location-form-actions")], [
            html.button(
              [
                attr.class("quiet"),
                attr.attribute("type", "button"),
                event.on_click(lift(Cancel)),
              ],
              [html.text("Cancel")],
            ),
            html.button(
              [attr.class("primary"), attr.attribute("type", "submit")],
              [
                html.text(case model.queue_id {
                  Some(_) -> "Save changes"
                  None -> "Create queue"
                }),
              ],
            ),
          ]),
          case model.error {
            Some(message) ->
              html.p(
                [attr.class("sign-in-error"), attr.attribute("role", "alert")],
                [html.text(message)],
              )
            None -> none()
          },
        ],
      ),
      html.aside([attr.class("preview-card")], [
        html.p([attr.class("preview-label")], [
          html.text(case model.queue_id {
            Some(_) -> "Configuration changes"
            None -> "Queue setup"
          }),
        ]),
        html.h3([], [
          html.text(case model.queue_id {
            Some(_) -> "Updates apply to future joins"
            None -> "Ready for your next operating session"
          }),
        ]),
        html.p([attr.class("muted")], [
          html.text(case model.queue_id {
            Some(_) ->
              "Saving configuration does not reset this queue's session or change existing tickets."
            None ->
              "Creating a queue saves its configuration only. No session is opened and visitors cannot join until the queue is activated and staff open a session."
          }),
        ]),
      ]),
    ]),
  ])
}

fn organization_select(
  model: Model,
  organizations: List(OrganizationOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  html.label([attr.class("field")], [
    html.text("Organization"),
    html.select(
      [
        attr.attribute("aria-label", "Organization"),
        attr.required(True),
        event.on_input(fn(value) { lift(OrganizationChanged(value)) }),
      ],
      [
        html.option(
          [
            attr.attribute("value", ""),
            attr.selected(model.organization_id == ""),
            attr.disabled(True),
          ],
          "Choose organization",
        ),
        ..list.map(organizations, fn(overview) {
          html.option(
            [
              attr.attribute("value", overview.organization.id),
              attr.selected(model.organization_id == overview.organization.id),
            ],
            overview.organization.name,
          )
        })
      ],
    ),
  ])
}

fn location_select(
  model: Model,
  locations: List(LocationOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  html.label([attr.class("field")], [
    html.text("Location"),
    html.select(
      [
        attr.attribute("aria-label", "Location"),
        attr.required(True),
        event.on_input(fn(value) { lift(LocationChanged(value)) }),
      ],
      [
        html.option(
          [
            attr.attribute("value", ""),
            attr.selected(model.location_id == ""),
            attr.disabled(True),
          ],
          "Choose location",
        ),
        ..list.map(locations, fn(location) {
          html.option(
            [
              attr.attribute("value", location.location.id),
              attr.selected(model.location_id == location.location.id),
            ],
            location.location.name,
          )
        })
      ],
    ),
  ])
}

fn service_select(
  model: Model,
  services: List(ServiceOverview),
  lift: fn(Message) -> message,
) -> Element(message) {
  html.label([attr.class("field")], [
    html.text("Service"),
    html.select(
      [
        attr.attribute("aria-label", "Service"),
        attr.required(True),
        event.on_input(fn(value) { lift(ServiceChanged(value)) }),
      ],
      [
        html.option(
          [
            attr.attribute("value", ""),
            attr.selected(model.service_id == ""),
            attr.disabled(True),
          ],
          "Choose service",
        ),
        ..list.map(services, fn(service) {
          html.option(
            [
              attr.attribute("value", service.service.id),
              attr.selected(model.service_id == service.service.id),
            ],
            service.service.name,
          )
        })
      ],
    ),
  ])
}

fn find_organization(
  organizations: List(OrganizationOverview),
  id: String,
) -> Option(OrganizationOverview) {
  case list.filter(organizations, fn(value) { value.organization.id == id }) {
    [value, ..] -> Some(value)
    [] -> None
  }
}

fn find_location(
  locations: List(LocationOverview),
  id: String,
) -> Option(LocationOverview) {
  case list.filter(locations, fn(value) { value.location.id == id }) {
    [value, ..] -> Some(value)
    [] -> None
  }
}

import client/invitation_acceptance
import client/navigation
import client/organization as organization_view
import client/organization_flow
import client/organization_overviews
import client/profile as profile_view
import client/queue_settings as queue_settings_view
import client/router
import client/sign_in as sign_in_view
import client/staff_access
import client/visitor_flow
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/uri.{type Uri}
import lustre
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import plinth/browser/location
import plinth/browser/web_storage
import plinth/browser/window
import rsvp
import shared.{type OrganizationOverview, type StaffInvitation, type User}
import shared/json as shared_json

type Model {
  Model(
    route: router.Route,
    notice: Option(String),
    organization_overviews: Option(List(OrganizationOverview)),
    organization_flow: organization_flow.Model,
    queue_settings: queue_settings_view.Model,
    authentication: sign_in_view.Model,
    visitor_flow: visitor_flow.Model,
    invitation_acceptance: invitation_acceptance.Model,
    staff_invitations: List(StaffInvitation),
    current_user: Option(User),
    profile: profile_view.Model,
  )
}

type Message {
  Navigate(router.Route)
  RouteChanged(router.Route)
  DismissNotice
  OrganizationOverviewsLoaded(
    Result(List(OrganizationOverview), rsvp.Error(String)),
  )
  Profile(profile_view.Message)
  CurrentUserLoaded(Result(User, rsvp.Error(String)))
  Authentication(sign_in_view.Message)
  OrganizationFlow(organization_flow.Message)
  QueueSettings(queue_settings_view.Message)
  InvitationAcceptance(invitation_acceptance.Message)
  VisitorFlow(visitor_flow.Message)
  StaffInvitationsLoaded(
    String,
    Result(List(StaffInvitation), rsvp.Error(String)),
  )
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let _ = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_arguments: Nil) -> #(Model, Effect(Message)) {
  let origin = window.self() |> window.location |> location.origin
  let route = case modem.initial_uri() {
    Ok(uri) -> router.from_uri(uri)
    Error(Nil) -> router.SignIn
  }
  let initial_user = get_stored_user()
  #(
    Model(
      route,
      None,
      None,
      organization_flow.init(),
      queue_settings_view.init() |> queue_settings_view.set_origin(origin),
      sign_in_view.init(),
      visitor_flow.init(route) |> visitor_flow.set_origin(origin),
      invitation_acceptance.init(),
      [],
      initial_user,
      profile_view.init(),
    ),
    effect.batch([
      route_effect(route, False, initial_user != None),
      modem.init(on_url_change),
    ]),
  )
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    Profile(_) if model.route != router.Profile -> #(model, effect.none())
    Profile(profile_message) -> {
      let #(profile, profile_effect) =
        profile_view.update(model.profile, profile_message)
      let current_user = case profile_view.updated_user(profile_message) {
        Some(user) -> {
          store_user(user)
          Some(user)
        }
        None ->
          case profile.session_expired {
            True -> {
              clear_stored_user()
              None
            }
            False -> model.current_user
          }
      }
      #(
        Model(..model, profile:, current_user:),
        effect.map(profile_effect, Profile),
      )
    }
    VisitorFlow(visitor_message) -> {
      let #(visitor_flow, visitor_effect, navigation) =
        visitor_flow.update(model.visitor_flow, model.route, visitor_message)
      let route = case navigation {
        Some(value) -> value
        None -> model.route
      }
      #(
        Model(..model, visitor_flow:, route:),
        effect.batch([
          effect.map(visitor_effect, VisitorFlow),
          case navigation {
            Some(value) ->
              effect.batch([
                modem.replace(router.to_path(value), None, None),
                effect.map(visitor_flow.route_effect(value), VisitorFlow),
              ])
            None -> effect.none()
          },
        ]),
      )
    }
    StaffInvitationsLoaded(organization_id, Ok(invitations)) -> {
      let kept =
        list.filter(model.staff_invitations, fn(invitation) {
          invitation.organization_id != organization_id
        })
      #(
        Model(..model, staff_invitations: list.append(kept, invitations)),
        effect.none(),
      )
    }
    StaffInvitationsLoaded(_, Error(_)) -> #(model, effect.none())
    CurrentUserLoaded(Ok(user)) -> {
      store_user(user)
      #(Model(..model, current_user: Some(user)), effect.none())
    }
    CurrentUserLoaded(Error(_)) -> {
      clear_stored_user()
      #(
        Model(..model, current_user: None, profile: profile_view.init()),
        effect.none(),
      )
    }
    OrganizationOverviewsLoaded(Ok(overviews)) -> {
      let route = case model.route {
        router.SignIn -> router.OrganizationOverview
        _ -> model.route
      }
      #(
        Model(..model, organization_overviews: Some(overviews), route:),
        effect.batch([
          case model.route == router.SignIn {
            True -> modem.push(router.to_path(route), None, None)
            False -> effect.none()
          },
          staff_invitations_effect(route, overviews),
        ]),
      )
    }
    OrganizationOverviewsLoaded(Error(_)) -> {
      clear_stored_user()
      let authentication = case model.route {
        router.SignIn -> model.authentication
        _ -> {
          let #(authentication, _) =
            sign_in_view.update(
              model.authentication,
              sign_in_view.SessionExpired,
            )
          authentication
        }
      }
      #(
        Model(
          ..model,
          organization_overviews: None,
          current_user: None,
          profile: profile_view.init(),
          route: router.SignIn,
          authentication:,
        ),
        modem.replace(router.to_path(router.SignIn), None, None),
      )
    }
    Navigate(route) -> {
      let visitor_flow = visitor_flow.route_changed(model.visitor_flow, route)
      #(
        Model(..model, route:, notice: None, visitor_flow:),
        effect.batch([
          modem.push(router.to_path(route), None, None),
          route_effect(
            route,
            model.organization_overviews != None,
            model.current_user != None,
          ),
          staff_invitations_effect(
            route,
            overview_values(model.organization_overviews),
          ),
        ]),
      )
    }
    RouteChanged(route) -> {
      let visitor_flow = visitor_flow.route_changed(model.visitor_flow, route)
      #(
        Model(..model, route:, notice: None, visitor_flow:),
        effect.batch([
          route_effect(
            route,
            model.organization_overviews != None,
            model.current_user != None,
          ),
          staff_invitations_effect(
            route,
            overview_values(model.organization_overviews),
          ),
        ]),
      )
    }
    Authentication(authentication_message) -> {
      let #(authentication, authentication_effect) =
        sign_in_view.update(model.authentication, authentication_message)
      case authentication_message {
        sign_in_view.SignedIn(Ok(user)) -> {
          store_user(user)
          #(
            Model(
              ..model,
              authentication:,
              current_user: Some(user),
              route: router.OrganizationOverview,
              organization_overviews: None,
            ),
            effect.batch([
              modem.push(
                router.to_path(router.OrganizationOverview),
                None,
                None,
              ),
              load_organizations(),
              effect.map(authentication_effect, Authentication),
            ]),
          )
        }
        sign_in_view.SignOut -> {
          clear_stored_user()
          #(
            Model(
              ..model,
              authentication:,
              current_user: None,
              profile: profile_view.init(),
              route: router.SignIn,
              organization_overviews: None,
            ),
            effect.batch([
              modem.replace(router.to_path(router.SignIn), None, None),
              effect.map(authentication_effect, Authentication),
            ]),
          )
        }
        _ -> #(
          Model(..model, authentication:),
          effect.map(authentication_effect, Authentication),
        )
      }
    }
    OrganizationFlow(organization_message) -> {
      let #(
        organization_flow,
        organization_effect,
        updated_overview,
        setup,
        refresh_invitations,
      ) =
        organization_flow.update(model.organization_flow, organization_message)
      let overviews = case updated_overview {
        Some(updated) ->
          organization_overviews.replace(model.organization_overviews, updated)
        None -> model.organization_overviews
      }
      let queue_settings = case setup {
        Some(organization_flow.QueueSetup(org_id, loc_id, service_id)) ->
          queue_settings_view.begin(
            model.queue_settings,
            org_id,
            loc_id,
            service_id,
          )
        None -> model.queue_settings
      }
      let route = case setup {
        Some(_) -> router.QueueSettings
        None -> model.route
      }
      #(
        Model(
          ..model,
          organization_flow:,
          organization_overviews: overviews,
          queue_settings:,
          route:,
        ),
        effect.batch([
          effect.map(organization_effect, OrganizationFlow),
          case organization_message {
            organization_flow.OrganizationAction(organization_view.MemberStatusSaved(
              _,
              _,
              Ok(_),
            )) -> load_organizations()
            organization_flow.OrganizationAction(organization_view.MemberAccessSaved(
              _,
              Ok(_),
            )) -> load_organizations()
            _ -> effect.none()
          },
          case route == model.route {
            True -> effect.none()
            False -> modem.push(router.to_path(route), None, None)
          },
          case refresh_invitations {
            True ->
              staff_invitations_effect(
                router.StaffAccess,
                overview_values(overviews),
              )
            False -> effect.none()
          },
        ]),
      )
    }
    QueueSettings(settings_message) -> {
      let #(queue_settings, settings_effect) =
        queue_settings_view.update(model.queue_settings, settings_message)
      let updated_overview =
        queue_settings_view.overview_from_message(settings_message)
      let overviews = case updated_overview {
        Some(updated) ->
          organization_overviews.replace(model.organization_overviews, updated)
        None -> model.organization_overviews
      }
      let route = case settings_message {
        queue_settings_view.Cancel
        | queue_settings_view.Created(Ok(_))
        | queue_settings_view.Updated(Ok(_)) -> router.OrganizationOverview
        _ -> model.route
      }
      #(
        Model(
          ..model,
          queue_settings:,
          organization_overviews: overviews,
          route:,
        ),
        effect.batch([
          effect.map(settings_effect, QueueSettings),
          case route == model.route {
            True -> effect.none()
            False -> modem.push(router.to_path(route), None, None)
          },
        ]),
      )
    }
    InvitationAcceptance(acceptance_message) -> {
      let #(invitation_acceptance, acceptance_effect) =
        invitation_acceptance.update(
          model.invitation_acceptance,
          case model.route {
            router.InvitationAccept(token) -> token
            _ -> None
          },
          acceptance_message,
        )
      #(
        Model(..model, invitation_acceptance:),
        effect.map(acceptance_effect, InvitationAcceptance),
      )
    }
    _ -> #(update_ui(model, message), effect.none())
  }
}

fn update_ui(model: Model, message: Message) -> Model {
  case message {
    Navigate(route) -> Model(..model, route:, notice: None)
    RouteChanged(route) -> Model(..model, route:, notice: None)
    DismissNotice -> Model(..model, notice: None)
    OrganizationOverviewsLoaded(_) -> model
    Profile(_) -> model
    CurrentUserLoaded(_) -> model
    Authentication(_) -> model
    OrganizationFlow(_) -> model
    QueueSettings(_) -> model
    InvitationAcceptance(_) -> model
    VisitorFlow(_) -> model
    StaffInvitationsLoaded(_, _) -> model
  }
}

const user_session_storage_key = "kewkew_current_user"

fn store_user(user: User) -> Nil {
  case web_storage.session() {
    Ok(storage) -> {
      let encoded = json.to_string(shared_json.user_to_json(user))
      let _ = web_storage.set_item(storage, user_session_storage_key, encoded)
      Nil
    }
    Error(_) -> Nil
  }
}

fn get_stored_user() -> Option(User) {
  case web_storage.session() {
    Ok(storage) ->
      case web_storage.get_item(storage, user_session_storage_key) {
        Ok(Some(stored_json)) ->
          case json.parse(stored_json, shared_json.user_decoder()) {
            Ok(user) -> Some(user)
            Error(_) -> None
          }
        _ -> None
      }
    Error(_) -> None
  }
}

fn clear_stored_user() -> Nil {
  case web_storage.session() {
    Ok(storage) -> {
      let _ = web_storage.remove_item(storage, user_session_storage_key)
      Nil
    }
    Error(_) -> Nil
  }
}

fn load_current_user() -> Effect(Message) {
  rsvp.get(
    "/api/auth/session",
    rsvp.expect_json(current_user_decoder(), CurrentUserLoaded),
  )
}

fn current_user_decoder() -> decode.Decoder(User) {
  use user <- decode.field("user", shared_json.user_decoder())
  decode.success(user)
}

fn load_organizations() -> Effect(Message) {
  rsvp.get(
    "/api/organizations",
    rsvp.expect_json(
      decode.list(shared_json.organization_overview_decoder()),
      OrganizationOverviewsLoaded,
    ),
  )
}

fn route_effect(
  route: router.Route,
  organizations_loaded: Bool,
  user_loaded: Bool,
) -> Effect(Message) {
  effect.batch([
    effect.map(visitor_flow.route_effect(route), VisitorFlow),
    case route {
      router.Profile -> effect.map(profile_view.load(), Profile)
      _ -> effect.none()
    },
    case route, organizations_loaded {
      router.Profile, False -> load_organizations()
      router.QueueDashboard, False -> load_organizations()
      router.QueueSettings, False -> load_organizations()
      router.TicketPreview, False -> load_organizations()
      router.OrganizationOverview, False -> load_organizations()
      router.StaffAccess, False -> load_organizations()
      _, _ -> effect.none()
    },
    case route, user_loaded {
      router.QueueDashboard, False -> load_current_user()
      router.QueueSettings, False -> load_current_user()
      router.TicketPreview, False -> load_current_user()
      router.OrganizationOverview, False -> load_current_user()
      router.StaffAccess, False -> load_current_user()
      _, _ -> effect.none()
    },
  ])
}

fn staff_invitations_effect(
  route: router.Route,
  overviews: List(OrganizationOverview),
) -> Effect(Message) {
  case route {
    router.StaffAccess ->
      overviews
      |> list.filter(fn(overview) { overview.can_manage })
      |> list.map(fn(overview) {
        effect.batch([
          effect.map(
            organization_view.load_members(overview.organization.id),
            fn(message) {
              OrganizationFlow(organization_flow.OrganizationAction(message))
            },
          ),
          rsvp.get(
            "/api/organizations/"
              <> overview.organization.id
              <> "/staff/invitations",
            rsvp.expect_json(
              decode.list(shared_json.staff_invitation_decoder()),
              fn(result) {
                StaffInvitationsLoaded(overview.organization.id, result)
              },
            ),
          ),
        ])
      })
      |> effect.batch
    _ -> effect.none()
  }
}

fn overview_values(
  overviews: Option(List(OrganizationOverview)),
) -> List(OrganizationOverview) {
  case overviews {
    Some(values) -> values
    None -> []
  }
}

fn on_url_change(uri: Uri) -> Message {
  RouteChanged(router.from_uri(uri))
}

fn view(model: Model) -> Element(Message) {
  case model.route {
    router.SignIn -> sign_in_screen(model)
    router.PublicQueue(_)
    | router.PublicLocation(_)
    | router.TicketTracking(_) -> visitor_page(model)
    router.InvitationAccept(token) ->
      invitation_acceptance.view(
        model.invitation_acceptance,
        token,
        InvitationAcceptance,
      )
    _ -> app_shell(model)
  }
}

fn visitor_page(model: Model) -> Element(Message) {
  visitor_flow.page(model.route, model.visitor_flow, Navigate, VisitorFlow)
}

fn sign_in_screen(model: Model) -> Element(Message) {
  sign_in_view.view(
    model.authentication.email,
    model.authentication.password,
    model.authentication.pending,
    model.authentication.error,
    fn(email) { Authentication(sign_in_view.EmailChanged(email)) },
    fn(password) { Authentication(sign_in_view.PasswordChanged(password)) },
    Authentication(sign_in_view.Submit),
  )
}

fn app_shell(model: Model) -> Element(Message) {
  html.div([attr.class("app-shell")], [
    header(
      model.current_user,
      model.organization_overviews,
      Authentication(sign_in_view.SignOut),
    ),
    html.div([attr.class("workspace")], [
      navigation.sidebar(
        model.route,
        has_admin_access(model.organization_overviews),
      ),
      html.main([attr.class("main-content")], [page_view(model)]),
    ]),
    navigation.mobile_nav(
      model.route,
      has_admin_access(model.organization_overviews),
    ),
    case model.notice {
      Some(message) ->
        html.div([attr.class("toast"), attr.attribute("role", "status")], [
          html.text(message),
          html.button(
            [
              attr.class("toast-close"),
              attr.attribute("aria-label", "Dismiss"),
              event.on_click(DismissNotice),
            ],
            [html.text("×")],
          ),
        ])
      None -> element.none()
    },
  ])
}

fn header(
  user: Option(User),
  overviews: Option(List(OrganizationOverview)),
  on_sign_out: Message,
) -> Element(Message) {
  html.header([attr.class("topbar")], [
    html.a(
      [
        attr.class("brand"),
        attr.attribute("href", router.to_path(router.QueueDashboard)),
      ],
      [
        html.span([attr.class("brand-mark")], [html.text("k")]),
        html.span([], [
          html.text("Kewkew"),
          html.small([], [html.text("Queue, without the wait")]),
        ]),
      ],
    ),
    html.div([attr.class("top-actions")], [
      html.button([attr.class("location-switch")], [
        html.text("⌖  " <> current_location_label(overviews) <> "  ⌄"),
      ]),
      html.a(
        [
          attr.href(router.to_path(router.Profile)),
          attr.class("profile-avatar-link"),
          attr.attribute("aria-label", "View my profile"),
        ],
        [navigation.avatar(user)],
      ),
      html.button(
        [
          attr.class("sign-out-button"),
          attr.attribute("type", "button"),
          event.on_click(on_sign_out),
        ],
        [html.text("Sign out")],
      ),
    ]),
  ])
}

fn current_location_label(
  overviews: Option(List(OrganizationOverview)),
) -> String {
  case overviews {
    None -> "Loading organization…"
    Some([]) -> "No organization access"
    Some([overview, ..]) ->
      case overview.locations {
        [location, ..] -> location.location.name
        [] -> overview.organization.name
      }
  }
}

fn page_view(model: Model) -> Element(Message) {
  case model.route {
    router.SignIn -> sign_in_screen(model)
    router.Profile -> profile_view.view(model.profile, Profile)
    router.QueueDashboard -> dashboard(model)
    router.VisitorJoin
    | router.PublicQueue(_)
    | router.PublicLocation(_)
    | router.TicketTracking(_) -> visitor_page(model)
    router.QueueSettings -> settings(model)
    router.TicketPreview -> ticket(model)
    router.OrganizationOverview ->
      organization_flow.view(
        model.organization_flow,
        model.organization_overviews,
        OrganizationFlow,
      )
    router.StaffAccess ->
      staff_access.view(
        model.organization_overviews,
        organization_flow.editor(model.organization_flow),
        model.staff_invitations,
        fn(message) {
          OrganizationFlow(organization_flow.OrganizationAction(message))
        },
      )
    router.InvitationAccept(_) -> element.none()
    router.NotFound -> not_found_page()
  }
}

fn not_found_page() -> Element(Message) {
  html.section([attr.class("page card not-found-card")], [
    html.p([attr.class("eyebrow")], [html.text("Page not found")]),
    html.h1([], [html.text("We couldn’t find that page")]),
    html.p([attr.class("subhead")], [
      html.text("Check the address or return to your workspace."),
    ]),
    html.a(
      [
        attr.class("primary not-found-link"),
        attr.attribute("href", router.to_path(router.QueueDashboard)),
      ],
      [html.text("Go to workspace")],
    ),
  ])
}

fn dashboard(model: Model) -> Element(Message) {
  html.section([attr.class("page")], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Your workspace")]),
        html.h1([], [html.text("Welcome to Kewkew")]),
        html.p([attr.class("subhead")], [
          html.text("Set up your queue workspace and keep service moving."),
        ]),
      ]),
      html.button(
        [attr.class("primary"), event.on_click(Navigate(router.VisitorJoin))],
        [
          html.text("＋  Add walk-in"),
        ],
      ),
    ]),
    html.div([attr.class("stats")], [
      stat("Waiting now", "—", "Queue data will appear here"),
      stat("Average wait", "—", "Based on recent service"),
      stat("Served today", "—", "Across your services"),
      stat("Queue status", "Not set up", "Create a queue to get started"),
    ]),
    live_queue_section(model),
    html.section([attr.class("lower-card card getting-started")], [
      html.h2([], [html.text("A smoother visit, step by step")]),
      html.div([attr.class("steps")], [
        step(
          "01",
          "Share your queue",
          "Visitors open a link or scan a QR code.",
        ),
        step(
          "02",
          "Welcome visitors",
          "They join from a phone and get a private ticket.",
        ),
        step(
          "03",
          "Serve the next person",
          "Your team manages the line from one shared view.",
        ),
      ]),
    ]),
  ])
}

fn live_queue_section(model: Model) -> Element(Message) {
  case model.organization_overviews {
    None ->
      html.section([attr.class("queue-card card")], [
        html.p([], [html.text("Loading your queues…")]),
      ])
    Some([]) ->
      html.section([attr.class("queue-card card empty-queue")], [
        html.h2([], [html.text("No queues available")]),
        html.p([], [
          html.text("Contact an organization administrator for queue access."),
        ]),
      ])
    Some(overviews) -> {
      let queue_cards =
        list.flat_map(overviews, fn(overview) {
          list.flat_map(overview.locations, fn(location) {
            list.flat_map(location.services, fn(service) {
              list.map(service.queues, fn(queue) {
                html.article([attr.class("queue-card card")], [
                  html.div([attr.class("page-heading")], [
                    html.div([], [
                      html.p([attr.class("eyebrow")], [
                        html.text(
                          overview.organization.name
                          <> " · "
                          <> location.location.name
                          <> " · "
                          <> service.service.name,
                        ),
                      ]),
                      html.h2([], [html.text(queue.name)]),
                    ]),
                  ]),
                  queue_settings_view.session_control(
                    model.queue_settings,
                    location.location.is_active,
                    service.service.is_active,
                    queue,
                    QueueSettings,
                  ),
                ])
              })
            })
          })
        })
      case queue_cards {
        [] ->
          html.section([attr.class("queue-card card empty-queue")], [
            html.h2([], [html.text("No queues available")]),
            html.p([], [
              html.text(case has_admin_access(model.organization_overviews) {
                True -> "Create a queue to start a live session."
                False -> "Ask an organization administrator to add a queue."
              }),
            ]),
            case has_admin_access(model.organization_overviews) {
              True ->
                html.button(
                  [
                    attr.class("secondary"),
                    event.on_click(Navigate(router.QueueSettings)),
                  ],
                  [html.text("Set up a queue")],
                )
              False -> html.text("")
            },
          ])
        _ -> html.div([attr.class("organization-overviews")], queue_cards)
      }
    }
  }
}

fn has_admin_access(overviews: Option(List(OrganizationOverview))) -> Bool {
  case overviews {
    Some(values) -> list.any(values, fn(value) { value.can_manage })
    None -> False
  }
}

fn stat(label: String, value: String, note: String) -> Element(Message) {
  html.article([attr.class("stat card")], [
    html.div([attr.class("stat-label")], [html.text(label)]),
    html.div([attr.class("stat-value")], [html.text(value)]),
    html.div([attr.class("stat-note")], [html.text(note)]),
  ])
}

fn step(
  number: String,
  title: String,
  description: String,
) -> Element(Message) {
  html.div([attr.class("step")], [
    html.span([attr.class("step-number")], [html.text(number)]),
    html.div([], [
      html.strong([], [html.text(title)]),
      html.p([], [html.text(description)]),
    ]),
  ])
}

fn ticket(_model: Model) -> Element(Message) {
  html.section([attr.class("ticket-view card")], [
    html.div([attr.class("ticket-check")], [html.text("✓")]),
    html.p([attr.class("eyebrow")], [html.text("Queue request")]),
    html.h1([], [html.text("Thanks for your request")]),
    html.p([attr.class("subhead")], [
      html.text("Your request is ready to send when the server is connected."),
    ]),
    html.div([attr.class("ticket-placeholder")], [html.text("—")]),
    html.p([attr.class("ticket-caption")], [
      html.text(
        "A ticket number will appear after the server confirms your place.",
      ),
    ]),
    html.div([attr.class("callout")], [
      html.text(
        "This preview does not create a queue ticket yet. Ticket creation and private tracking will use the server API.",
      ),
    ]),
    html.button(
      [attr.class("secondary"), event.on_click(Navigate(router.VisitorJoin))],
      [
        html.text("Back to queue details"),
      ],
    ),
  ])
}

fn settings(model: Model) -> Element(Message) {
  queue_settings_view.view(
    model.queue_settings,
    model.organization_overviews,
    fn(message) { QueueSettings(message) },
  )
}

import client/organization as organization_view
import client/organization_overviews
import client/queue_settings as queue_settings_view
import client/router
import client/sign_in as sign_in_view
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri.{type Uri}
import lustre
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import rsvp
import shared.{type OrganizationOverview}
import shared/json as shared_json

type Service {
  FoodSupport
  CommunityAdvice
}

type Model {
  Model(
    route: router.Route,
    service: Service,
    first_name: String,
    last_name: String,
    identity_required: Bool,
    notice: Option(String),
    organization_overviews: Option(List(OrganizationOverview)),
    organization: organization_view.Model,
    queue_settings: queue_settings_view.Model,
    authentication: sign_in_view.Model,
  )
}

type Message {
  Navigate(router.Route)
  RouteChanged(router.Route)
  SelectService(Service)
  UpdateFirstName(String)
  UpdateLastName(String)
  Join
  DismissNotice
  ToggleIdentityPolicy
  OrganizationOverviewsLoaded(
    Result(List(OrganizationOverview), rsvp.Error(String)),
  )
  Authentication(sign_in_view.Message)
  Organization(organization_view.Message)
  QueueSettings(queue_settings_view.Message)
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let _ = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_arguments: Nil) -> #(Model, Effect(Message)) {
  let route = case modem.initial_uri() {
    Ok(uri) -> router.from_uri(uri)
    Error(Nil) -> router.SignIn
  }
  #(
    Model(
      route,
      FoodSupport,
      "",
      "",
      True,
      None,
      None,
      organization_view.init(),
      queue_settings_view.init(),
      sign_in_view.init(),
    ),
    effect.batch([route_effect(route, False), modem.init(on_url_change)]),
  )
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    OrganizationOverviewsLoaded(Ok(overviews)) -> {
      let route = case model.route {
        router.SignIn -> router.OrganizationOverview
        _ -> model.route
      }
      #(
        Model(..model, organization_overviews: Some(overviews), route:),
        case model.route == router.SignIn {
          True -> modem.push(router.to_path(route), None, None)
          False -> effect.none()
        },
      )
    }
    OrganizationOverviewsLoaded(Error(_)) -> {
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
          route: router.SignIn,
          authentication:,
        ),
        modem.replace(router.to_path(router.SignIn), None, None),
      )
    }
    Navigate(route) -> {
      #(
        Model(..model, route:, notice: None),
        effect.batch([
          modem.push(router.to_path(route), None, None),
          route_effect(route, model.organization_overviews != None),
        ]),
      )
    }
    RouteChanged(route) -> #(
      Model(..model, route:, notice: None),
      route_effect(route, model.organization_overviews != None),
    )
    Authentication(authentication_message) -> {
      let #(authentication, authentication_effect) =
        sign_in_view.update(model.authentication, authentication_message)
      case authentication_message {
        sign_in_view.SignedIn(Ok(_)) -> #(
          Model(
            ..model,
            authentication:,
            route: router.OrganizationOverview,
            organization_overviews: None,
          ),
          effect.batch([
            modem.push(router.to_path(router.OrganizationOverview), None, None),
            load_organizations(),
            effect.map(authentication_effect, Authentication),
          ]),
        )
        sign_in_view.SignOut -> #(
          Model(
            ..model,
            authentication:,
            route: router.SignIn,
            organization_overviews: None,
          ),
          effect.batch([
            modem.replace(router.to_path(router.SignIn), None, None),
            effect.map(authentication_effect, Authentication),
          ]),
        )
        _ -> #(
          Model(..model, authentication:),
          effect.map(authentication_effect, Authentication),
        )
      }
    }
    Organization(organization_message) -> {
      let #(organization, organization_effect) =
        organization_view.update(model.organization, organization_message)
      let route = case organization_message {
        organization_view.CreateQueue(_, _, _) -> router.QueueSettings
        _ -> model.route
      }
      let queue_settings = case organization_message {
        organization_view.CreateQueue(org_id, loc_id, service_id) ->
          queue_settings_view.begin(
            model.queue_settings,
            org_id,
            loc_id,
            service_id,
          )
        _ -> model.queue_settings
      }
      let updated_overview =
        organization_overviews.from_message(organization_message)
      let overviews = case updated_overview {
        Some(updated) ->
          organization_overviews.replace(model.organization_overviews, updated)
        None -> model.organization_overviews
      }
      #(
        Model(
          ..model,
          organization:,
          organization_overviews: overviews,
          queue_settings:,
          route:,
        ),
        effect.batch([
          effect.map(organization_effect, Organization),
          case route == model.route {
            True -> effect.none()
            False -> modem.push(router.to_path(route), None, None)
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
        queue_settings_view.Cancel | queue_settings_view.Created(Ok(_)) ->
          router.OrganizationOverview
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
    _ -> #(update_ui(model, message), effect.none())
  }
}

fn update_ui(model: Model, message: Message) -> Model {
  case message {
    Navigate(route) -> Model(..model, route:, notice: None)
    RouteChanged(route) -> Model(..model, route:, notice: None)
    SelectService(service) -> Model(..model, service:, notice: None)
    UpdateFirstName(value) -> Model(..model, first_name: value, notice: None)
    UpdateLastName(value) -> Model(..model, last_name: value, notice: None)
    Join ->
      case
        model.identity_required && model.service == FoodSupport,
        blank(model.first_name),
        blank(model.last_name)
      {
        True, True, _ ->
          Model(..model, notice: Some("Enter your first name to continue."))
        True, False, True ->
          Model(..model, notice: Some("Enter your last name to continue."))
        _, _, _ ->
          Model(
            ..model,
            route: router.TicketPreview,
            notice: Some(
              "Ticket creation will be available when the server API is connected.",
            ),
          )
      }
    DismissNotice -> Model(..model, notice: None)
    ToggleIdentityPolicy ->
      Model(..model, identity_required: !model.identity_required, notice: None)
    OrganizationOverviewsLoaded(_) -> model
    Authentication(_) -> model
    Organization(_) -> model
    QueueSettings(_) -> model
  }
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
) -> Effect(Message) {
  case route, organizations_loaded {
    router.QueueDashboard, False -> load_organizations()
    router.QueueSettings, False -> load_organizations()
    router.TicketPreview, False -> load_organizations()
    router.OrganizationOverview, False -> load_organizations()
    _, _ -> effect.none()
  }
}

fn on_url_change(uri: Uri) -> Message {
  RouteChanged(router.from_uri(uri))
}

fn blank(value: String) -> Bool {
  string.trim(value) == ""
}

fn view(model: Model) -> Element(Message) {
  case model.route {
    router.SignIn -> sign_in_screen(model)
    _ -> app_shell(model)
  }
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
    header(model.organization_overviews, Authentication(sign_in_view.SignOut)),
    html.div([attr.class("workspace")], [
      sidebar(model.route, has_admin_access(model.organization_overviews)),
      html.main([attr.class("main-content")], [page_view(model)]),
    ]),
    html.nav(
      [
        attr.class("mobile-nav"),
        attr.attribute("aria-label", "Main navigation"),
      ],
      [
        nav_button("▦", "Queue", router.QueueDashboard, model.route),
        nav_button("↗", "Join", router.VisitorJoin, model.route),
        nav_button("⚙", "Settings", router.QueueSettings, model.route),
        nav_button(
          "◇",
          "Organization",
          router.OrganizationOverview,
          model.route,
        ),
      ],
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
      html.div(
        [
          attr.class("avatar"),
          attr.attribute("aria-label", "Signed in as Alex Morgan"),
        ],
        [html.text("AM")],
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

fn sidebar(active: router.Route, can_manage: Bool) -> Element(Message) {
  html.aside([attr.class("sidebar")], [
    html.p([attr.class("side-label")], [html.text("Workspace")]),
    html.nav(
      [attr.class("nav-list"), attr.attribute("aria-label", "Workspace")],
      [
        nav_button("▦", "Live queue", router.QueueDashboard, active),
        nav_button("↗", "Join a queue", router.VisitorJoin, active),
        nav_button("⚙", "Queue settings", router.QueueSettings, active),
      ],
    ),
    html.nav(
      [attr.class("nav-list"), attr.attribute("aria-label", "Organization")],
      [nav_button("◇", "Organization", router.OrganizationOverview, active)],
    ),
    case can_manage {
      True ->
        html.div([], [
          html.p([attr.class("side-label")], [html.text("Manage")]),
          html.nav(
            [attr.class("nav-list"), attr.attribute("aria-label", "Manage")],
            [
              nav_button("◇", "Services", router.QueueSettings, active),
              nav_button("◷", "Activity", router.QueueDashboard, active),
              nav_button("▤", "Reports", router.QueueDashboard, active),
            ],
          ),
        ])
      False -> element.none()
    },
    html.div([attr.class("side-card")], [
      html.strong([], [html.text("Need a hand?")]),
      html.p([], [
        html.text("Get your team set up and make your first queue in minutes."),
      ]),
      html.a([attr.attribute("href", "#help")], [
        html.text("Visit help center →"),
      ]),
    ]),
  ])
}

fn nav_button(
  icon: String,
  label: String,
  route: router.Route,
  active: router.Route,
) -> Element(Message) {
  html.a(
    [
      attr.classes([#("nav-button", True), #("active", route == active)]),
      attr.attribute("href", router.to_path(route)),
      attr.attribute("aria-current", case route == active {
        True -> "page"
        _ -> "false"
      }),
    ],
    [
      html.span(
        [attr.class("nav-icon"), attr.attribute("aria-hidden", "true")],
        [html.text(icon)],
      ),
      html.text(label),
    ],
  )
}

fn page_view(model: Model) -> Element(Message) {
  case model.route {
    router.SignIn -> sign_in_screen(model)
    router.QueueDashboard -> dashboard(model)
    router.VisitorJoin -> join_page(model)
    router.QueueSettings -> settings(model)
    router.TicketPreview -> ticket(model)
    router.OrganizationOverview -> organization_page(model)
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
    organization_overviews(model),
    html.section([attr.class("queue-card card empty-queue")], [
      html.div([attr.class("empty-icon")], [html.text("▦")]),
      html.h2([], [html.text("Your live queue will show here")]),
      html.p([], [
        html.text(
          "Connect the server to see waiting visitors and manage tickets from this workspace.",
        ),
      ]),
      html.button(
        [
          attr.class("secondary"),
          event.on_click(Navigate(router.QueueSettings)),
        ],
        [html.text("Set up a queue")],
      ),
    ]),
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

fn organization_page(model: Model) -> Element(Message) {
  html.section([attr.class("page")], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Organization")]),
        html.h1([], [
          html.text(current_organization_name(model.organization_overviews)),
        ]),
        html.p([attr.class("subhead")], [
          html.text("Locations, services, and queues in your workspace."),
        ]),
      ]),
    ]),
    organization_overviews(model),
  ])
}

fn current_organization_name(
  overviews: Option(List(OrganizationOverview)),
) -> String {
  case overviews {
    Some([overview, ..]) -> overview.organization.name
    _ -> "Your organization"
  }
}

fn organization_overviews(model: Model) -> Element(Message) {
  case model.organization_overviews {
    None ->
      html.section([attr.class("card setup-card")], [
        html.p([], [html.text("Loading your organization…")]),
      ])
    Some([]) ->
      html.section([attr.class("card setup-card")], [
        html.h2([], [html.text("No active organization access")]),
        html.p([], [
          html.text("Contact an organization administrator for access."),
        ]),
      ])
    Some(overviews) ->
      html.div(
        [attr.class("organization-overviews")],
        list.map(overviews, fn(overview) {
          organization_view.overview_card(
            overview,
            model.organization,
            fn(message) { Organization(message) },
          )
        }),
      )
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

fn join_page(model: Model) -> Element(Message) {
  html.section([attr.class("visitor-page")], [
    html.div([attr.class("visitor-copy")], [
      html.p([attr.class("eyebrow")], [html.text("Riverside Community Hub")]),
      html.h1([], [
        html.text("Your place in line, "),
        html.span([attr.class("text-green")], [html.text("without the wait.")]),
      ]),
      html.p([attr.class("subhead")], [
        html.text(
          "Join from your phone, then take a seat or step outside. We’ll keep your place up to date.",
        ),
      ]),
      html.div([attr.class("trust-points")], [
        trust("No app or account needed"),
        trust("See your place and estimated wait"),
        trust("Your queue details stay private"),
      ]),
    ]),
    html.section([attr.class("join-card card")], [
      html.div([attr.class("business")], [
        html.div([attr.class("business-mark")], [html.text("R")]),
        html.div([], [
          html.strong([], [html.text("Riverside Community Hub")]),
          html.small([], [html.text("Availability will load from the server")]),
        ]),
      ]),
      html.h2([], [html.text("What can we help with?")]),
      html.p([attr.class("card-hint")], [
        html.text("Choose a service to join its queue."),
      ]),
      service_button(
        FoodSupport,
        "Community food support",
        "Names required",
        model.service,
      ),
      service_button(
        CommunityAdvice,
        "Community advice",
        "Join anonymously",
        model.service,
      ),
      case model.identity_required && model.service == FoodSupport {
        True ->
          html.div([], [
            field(
              "First name",
              "first-name",
              "e.g. Jordan",
              model.first_name,
              UpdateFirstName,
            ),
            field(
              "Last name",
              "last-name",
              "e.g. Morgan",
              model.last_name,
              UpdateLastName,
            ),
          ])
        False -> element.none()
      },
      html.button([attr.class("primary full-width"), event.on_click(Join)], [
        html.text(case model.service {
          FoodSupport -> "Join the queue  →"
          CommunityAdvice -> "Get an anonymous ticket  →"
        }),
      ]),
      html.p([attr.class("privacy-note")], [
        html.text(
          "Only share the information needed for this service. Your private ticket link is for you.",
        ),
      ]),
    ]),
  ])
}

fn trust(copy: String) -> Element(Message) {
  html.div([attr.class("trust-point")], [
    html.span([attr.class("check")], [html.text("✓")]),
    html.text(copy),
  ])
}

fn service_button(
  service: Service,
  title: String,
  detail: String,
  selected: Service,
) -> Element(Message) {
  html.button(
    [
      attr.classes([
        #("service-option", True),
        #("selected", service == selected),
      ]),
      event.on_click(SelectService(service)),
    ],
    [
      html.span([], [
        html.strong([], [html.text(title)]),
        html.small([], [html.text(detail)]),
      ]),
      html.span(
        [attr.classes([#("radio", True), #("checked", service == selected)])],
        [],
      ),
    ],
  )
}

fn field(
  label: String,
  id: String,
  placeholder: String,
  value: String,
  handler: fn(String) -> Message,
) -> Element(Message) {
  html.label([attr.class("field"), attr.attribute("for", id)], [
    html.text(label),
    html.input([
      attr.attribute("id", id),
      attr.attribute("type", "text"),
      attr.attribute("placeholder", placeholder),
      attr.attribute("value", value),
      attr.attribute("autocomplete", case id {
        "first-name" -> "given-name"
        _ -> "family-name"
      }),
      event.on_input(handler),
    ]),
  ])
}

fn ticket(model: Model) -> Element(Message) {
  let name = case model.service, blank(model.first_name) {
    FoodSupport, False -> model.first_name
    _, _ -> "there"
  }
  html.section([attr.class("ticket-view card")], [
    html.div([attr.class("ticket-check")], [html.text("✓")]),
    html.p([attr.class("eyebrow")], [html.text("Queue request")]),
    html.h1([], [html.text("Thanks, "), html.span([], [html.text(name)])]),
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

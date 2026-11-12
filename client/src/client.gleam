import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

type Page {
  LiveQueue
  JoinQueue
  QueueSettings
  Ticket
}

type Service {
  FoodSupport
  CommunityAdvice
}

type Model {
  Model(
    page: Page,
    service: Service,
    first_name: String,
    last_name: String,
    identity_required: Bool,
    notice: Option(String),
  )
}

type Message {
  Navigate(Page)
  SelectService(Service)
  UpdateFirstName(String)
  UpdateLastName(String)
  Join
  DismissNotice
  ToggleIdentityPolicy
}

pub fn main() -> Nil {
  let app = lustre.simple(init, update, view)
  let _ = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_arguments: Nil) -> Model {
  Model(LiveQueue, FoodSupport, "", "", True, None)
}

fn update(model: Model, message: Message) -> Model {
  case message {
    Navigate(page) -> Model(..model, page:, notice: None)
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
            page: Ticket,
            notice: Some(
              "Ticket creation will be available when the server API is connected.",
            ),
          )
      }
    DismissNotice -> Model(..model, notice: None)
    ToggleIdentityPolicy ->
      Model(..model, identity_required: !model.identity_required, notice: None)
  }
}

fn blank(value: String) -> Bool {
  string.trim(value) == ""
}

fn view(model: Model) -> Element(Message) {
  html.div([attr.class("app-shell")], [
    header(),
    html.div([attr.class("workspace")], [
      sidebar(model.page),
      html.main([attr.class("main-content")], [page_view(model)]),
    ]),
    html.nav(
      [
        attr.class("mobile-nav"),
        attr.attribute("aria-label", "Main navigation"),
      ],
      [
        nav_button("▦", "Queue", LiveQueue, model.page),
        nav_button("↗", "Join", JoinQueue, model.page),
        nav_button("⚙", "Settings", QueueSettings, model.page),
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

fn header() -> Element(Message) {
  html.header([attr.class("topbar")], [
    html.a([attr.class("brand"), attr.attribute("href", "#home")], [
      html.span([attr.class("brand-mark")], [html.text("k")]),
      html.span([], [
        html.text("Kewkew"),
        html.small([], [html.text("Queue, without the wait")]),
      ]),
    ]),
    html.div([attr.class("top-actions")], [
      html.button([attr.class("location-switch")], [
        html.text("⌖  Riverside Community Hub  ⌄"),
      ]),
      html.div(
        [
          attr.class("avatar"),
          attr.attribute("aria-label", "Signed in as Alex Morgan"),
        ],
        [html.text("AM")],
      ),
    ]),
  ])
}

fn sidebar(active: Page) -> Element(Message) {
  html.aside([attr.class("sidebar")], [
    html.p([attr.class("side-label")], [html.text("Workspace")]),
    html.nav(
      [attr.class("nav-list"), attr.attribute("aria-label", "Workspace")],
      [
        nav_button("▦", "Live queue", LiveQueue, active),
        nav_button("↗", "Join a queue", JoinQueue, active),
        nav_button("⚙", "Queue settings", QueueSettings, active),
      ],
    ),
    html.p([attr.class("side-label")], [html.text("Manage")]),
    html.nav([attr.class("nav-list"), attr.attribute("aria-label", "Manage")], [
      nav_button("◇", "Services", QueueSettings, active),
      nav_button("◷", "Activity", LiveQueue, active),
      nav_button("▤", "Reports", LiveQueue, active),
    ]),
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
  page: Page,
  active: Page,
) -> Element(Message) {
  html.button(
    [
      attr.classes([#("nav-button", True), #("active", page == active)]),
      attr.attribute("aria-current", case page == active {
        True -> "page"
        _ -> "false"
      }),
      event.on_click(Navigate(page)),
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
  case model.page {
    LiveQueue -> dashboard()
    JoinQueue -> join_page(model)
    QueueSettings -> settings(model)
    Ticket -> ticket(model)
  }
}

fn dashboard() -> Element(Message) {
  html.section([attr.class("page")], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Your workspace")]),
        html.h1([], [html.text("Welcome to Kewkew")]),
        html.p([attr.class("subhead")], [
          html.text("Set up your queue workspace and keep service moving."),
        ]),
      ]),
      html.button([attr.class("primary"), event.on_click(Navigate(JoinQueue))], [
        html.text("＋  Add walk-in"),
      ]),
    ]),
    html.div([attr.class("stats")], [
      stat("Waiting now", "—", "Queue data will appear here"),
      stat("Average wait", "—", "Based on recent service"),
      stat("Served today", "—", "Across your services"),
      stat("Queue status", "Not set up", "Create a queue to get started"),
    ]),
    html.section([attr.class("queue-card card empty-queue")], [
      html.div([attr.class("empty-icon")], [html.text("▦")]),
      html.h2([], [html.text("Your live queue will show here")]),
      html.p([], [
        html.text(
          "Connect the server to see waiting visitors and manage tickets from this workspace.",
        ),
      ]),
      html.button(
        [attr.class("secondary"), event.on_click(Navigate(QueueSettings))],
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
    html.button([attr.class("secondary"), event.on_click(Navigate(JoinQueue))], [
      html.text("Back to queue details"),
    ]),
  ])
}

fn settings(model: Model) -> Element(Message) {
  html.section([], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Queue configuration")]),
        html.h1([], [html.text("Make this queue yours")]),
        html.p([attr.class("subhead")], [
          html.text(
            "Choose what visitors see and what your team needs to serve them.",
          ),
        ]),
      ]),
      html.span([attr.class("status")], [html.text("Not connected")]),
    ]),
    html.div([attr.class("settings-layout")], [
      html.section([attr.class("settings-card card")], [
        html.h2([], [html.text("Community food support")]),
        html.p([attr.class("card-hint")], [
          html.text(
            "Riverside Community Hub · Visitors join from a QR code or shared link.",
          ),
        ]),
        html.label([attr.class("field")], [
          html.text("Queue name"),
          html.input([
            attr.attribute("type", "text"),
            attr.attribute("value", "Community food support"),
            attr.attribute("disabled", ""),
          ]),
        ]),
        html.p([attr.class("field-label")], [html.text("Visitor information")]),
        policy(
          "First and last name required",
          "Visitors share their name so staff can identify them.",
          model.identity_required,
        ),
        policy(
          "Anonymous ticket",
          "Visitors get a ticket number without sharing a name.",
          !model.identity_required,
        ),
        html.div([attr.class("inline-note")], [
          html.text(
            "Settings will be saved to the server when the API is available.",
          ),
        ]),
      ]),
      html.aside([attr.class("preview-card")], [
        html.p([attr.class("preview-label")], [html.text("Visitor preview")]),
        html.h3([], [html.text("Joining your queue")]),
        html.div([attr.class("preview-inner")], [
          html.strong([], [html.text("Community food support")]),
          case model.identity_required {
            True ->
              html.div([attr.class("preview-fields")], [
                html.div([], [html.text("First name")]),
                html.div([], [html.text("Last name")]),
              ])
            False ->
              html.p([attr.class("preview-anonymous")], [
                html.text("No personal details required"),
              ])
          },
          html.div([attr.class("preview-button")], [
            html.text("Join the queue →"),
          ]),
        ]),
      ]),
    ]),
  ])
}

fn policy(
  title: String,
  description: String,
  selected: Bool,
) -> Element(Message) {
  html.button(
    [
      attr.classes([#("policy-option", True), #("selected", selected)]),
      event.on_click(ToggleIdentityPolicy),
    ],
    [
      html.span([], [
        html.strong([], [html.text(title)]),
        html.small([], [html.text(description)]),
      ]),
      html.span(
        [attr.classes([#("policy-radio", True), #("checked", selected)])],
        [],
      ),
    ],
  )
}

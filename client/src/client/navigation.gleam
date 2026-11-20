import client/router
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import shared

/// Render the desktop workspace navigation for the signed-in staff role.
pub fn sidebar(active: router.Route, can_manage: Bool) -> Element(message) {
  case can_manage {
    True ->
      html.aside([attr.class("sidebar")], [
        html.p([attr.class("side-label")], [html.text("Workspace")]),
        html.nav(
          [attr.class("nav-list"), attr.attribute("aria-label", "Workspace")],
          [
            nav_button("▦", "Live queues", router.QueueDashboard, active),
            nav_button("⚙", "Queue settings", router.QueueSettings, active),
          ],
        ),
        html.nav(
          [attr.class("nav-list"), attr.attribute("aria-label", "Organization")],
          [
            nav_button("◇", "Organization", router.OrganizationOverview, active),
            nav_button("♙", "Staff access", router.StaffAccess, active),
          ],
        ),
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
        ]),
        html.div([attr.class("side-card")], [
          html.strong([], [html.text("Need a hand?")]),
          html.p([], [
            html.text(
              "Get your team set up and make your first queue in minutes.",
            ),
          ]),
          html.a([attr.attribute("href", "#help")], [
            html.text("Visit help center →"),
          ]),
        ]),
      ])
    False ->
      html.aside([attr.class("sidebar")], [
        html.p([attr.class("side-label")], [html.text("Workspace")]),
        html.nav(
          [attr.class("nav-list"), attr.attribute("aria-label", "Workspace")],
          [nav_button("▦", "Live queues", router.QueueDashboard, active)],
        ),
      ])
  }
}

/// Keep mobile navigation consistent with the role-specific desktop menu.
pub fn mobile_nav(active: router.Route, can_manage: Bool) -> Element(message) {
  let links = case can_manage {
    True -> [
      nav_button("▦", "Queue", router.QueueDashboard, active),
      nav_button("↗", "Join", router.VisitorJoin, active),
      nav_button("⚙", "Settings", router.QueueSettings, active),
      nav_button("◇", "Organization", router.OrganizationOverview, active),
    ]
    False -> [nav_button("▦", "Live queue", router.QueueDashboard, active)]
  }
  html.nav(
    [attr.class("mobile-nav"), attr.attribute("aria-label", "Main navigation")],
    links,
  )
}

fn nav_button(
  icon: String,
  label: String,
  route: router.Route,
  active: router.Route,
) -> Element(message) {
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

/// Compute initials for a user's display name.
/// Single words return their first letter ("Jane" -> "J").
/// Multiple words return first and last initials ("Alex Morgan" -> "AM", "Alex Parker Morgan" -> "AM").
/// Empty or whitespace-only inputs return an empty string.
pub fn user_initials(name: String) -> String {
  let parts =
    string.split(name, " ")
    |> list.map(string.trim)
    |> list.filter(fn(part) { part != "" })

  case parts {
    [] -> ""
    [single] -> string.slice(single, 0, 1) |> string.uppercase
    [first, ..rest] -> {
      let last = case list.last(rest) {
        Ok(l) -> l
        Error(Nil) -> ""
      }
      { string.slice(first, 0, 1) <> string.slice(last, 0, 1) }
      |> string.uppercase
    }
  }
}

/// Render a dynamic avatar for the top navigation bar.
/// When a user profile is present, displays their custom image (if available) or initials.
/// When user name is missing, falls back to email initial.
/// When no user is signed in, displays an accessible placeholder dash.
pub fn avatar(user: Option(shared.User)) -> Element(message) {
  case user {
    Some(u) -> {
      let display_name = case string.trim(u.name) {
        "" ->
          case string.trim(u.email) {
            "" -> "Signed in"
            email -> email
          }
        name -> name
      }
      let aria_label = "Signed in as " <> display_name
      let content = case u.image {
        Some(url) if url != "" ->
          html.img([
            attr.class("avatar-image"),
            attr.attribute("src", url),
            attr.attribute("alt", display_name),
          ])
        _ -> {
          let initials = case user_initials(u.name) {
            "" ->
              case string.trim(u.email) {
                "" -> "—"
                email -> string.slice(email, 0, 1) |> string.uppercase
              }
            computed -> computed
          }
          html.text(initials)
        }
      }
      html.div(
        [
          attr.class("avatar"),
          attr.attribute("title", display_name),
          attr.attribute("aria-label", aria_label),
        ],
        [content],
      )
    }
    None ->
      html.div(
        [
          attr.class("avatar"),
          attr.attribute("title", "Signed in"),
          attr.attribute("aria-label", "Signed in"),
        ],
        [html.text("—")],
      )
  }
}

//// Browser routes for the current client views.

import gleam/list
import gleam/option.{type Option}
import gleam/result

import gleam/uri.{type Uri}

pub type Route {
  SignIn
  QueueDashboard
  VisitorJoin
  PublicQueue(String)
  QueueSettings
  TicketPreview
  OrganizationOverview
  StaffAccess
  InvitationAccept(Option(String))
  NotFound
}

/// Match the URI path received from Modem to a client route.
pub fn from_uri(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] -> SignIn
    ["sign-in"] | ["sign-out"] -> SignIn
    ["staff"] -> QueueDashboard
    ["staff", "organization"] -> OrganizationOverview
    ["staff", "access"] -> StaffAccess
    ["staff", "settings"] -> QueueSettings
    ["staff", "ticket"] -> TicketPreview
    ["visitor", "join"] -> VisitorJoin
    ["invite", "accept"] -> InvitationAccept(token_from_query(uri.query))
    ["q", public_id] if public_id != "" -> PublicQueue(public_id)
    _ -> NotFound
  }
}

/// Match a raw href such as "/invite/accept?token=abc". Useful for tests and
/// anywhere you only have a string.
pub fn from_href(href: String) -> Route {
  case uri.parse(href) {
    Ok(uri) -> from_uri(uri)
    Error(Nil) -> NotFound
  }
}

fn token_from_query(query: Option(String)) -> Option(String) {
  query
  |> option.to_result(Nil)
  |> result.try(uri.parse_query)
  |> result.try(list.key_find(_, "token"))
  |> result.try(fn(token) {
    case token {
      "" -> Error(Nil)
      _ -> Ok(token)
    }
  })
  |> option.from_result
}

/// Return the canonical browser pathname for a known route.
pub fn to_path(route: Route) -> String {
  case route {
    SignIn -> "/sign-in"
    QueueDashboard -> "/staff"
    VisitorJoin -> "/visitor/join"
    PublicQueue(public_id) -> "/q/" <> public_id
    QueueSettings -> "/staff/settings"
    TicketPreview -> "/staff/ticket"
    OrganizationOverview -> "/staff/organization"
    StaffAccess -> "/staff/access"
    InvitationAccept(_) -> "/invite/accept"
    NotFound -> "/404"
  }
}

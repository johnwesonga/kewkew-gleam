/// Browser routes for the current client views.
import gleam/string
import gleam/uri.{type Uri}

pub type Route {
  SignIn
  QueueDashboard
  VisitorJoin
  PublicQueue(String)
  QueueSettings
  TicketPreview
  OrganizationOverview
  NotFound
}

/// Match a browser pathname to a client route. The root path opens sign-in;
/// unknown paths render the not-found view rather than silently showing a page.
pub fn from_path(path: String) -> Route {
  case path {
    "/" -> SignIn
    "/sign-in" -> SignIn
    "/sign-out" -> SignIn
    "/staff" -> QueueDashboard
    "/staff/organization" -> OrganizationOverview
    "/staff/settings" -> QueueSettings
    "/staff/ticket" -> TicketPreview
    "/visitor/join" -> VisitorJoin
    _ ->
      case string.starts_with(path, "/q/") {
        True ->
          case string.drop_start(path, 3) {
            "" -> NotFound
            public_id -> PublicQueue(public_id)
          }
        False -> NotFound
      }
  }
}

/// Match the URI path received from Modem to a client route.
pub fn from_uri(uri: Uri) -> Route {
  from_path(uri.path)
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
    NotFound -> "/404"
  }
}

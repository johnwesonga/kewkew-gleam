import client/router
import gleam/list
import gleam/option.{None, Some}
import gleam/uri

pub fn parses_known_routes_test() {
  assert router.from_href("/") == router.SignIn
  assert router.from_href("/sign-in") == router.SignIn
  assert router.from_href("/sign-out") == router.SignIn
  assert router.from_href("/staff") == router.QueueDashboard
  assert router.from_href("/staff/organization") == router.OrganizationOverview
  assert router.from_href("/staff/access") == router.StaffAccess
  assert router.from_href("/staff/settings") == router.QueueSettings
  assert router.from_href("/staff/ticket") == router.TicketPreview
  assert router.from_href("/visitor/join") == router.VisitorJoin
  assert router.from_href("/q/5fa37d63ac4e4e578563f9d45d7815c0")
    == router.PublicQueue("5fa37d63ac4e4e578563f9d45d7815c0")
}

pub fn invitation_route_preserves_token_from_initial_uri_query_test() {
  let location =
    uri.Uri(
      ..uri.empty,
      path: "/invite/accept",
      query: Some("token=secure-token"),
    )
  assert router.from_uri(location)
    == router.InvitationAccept(Some("secure-token"))
}

pub fn invitation_route_decodes_token_from_path_test() {
  assert router.from_href("/invite/accept?token=secure-token")
    == router.InvitationAccept(Some("secure-token"))
  assert router.from_href("/invite/accept") == router.InvitationAccept(None)
}

pub fn unknown_paths_fall_back_to_not_found_test() {
  assert router.from_href("/unknown") == router.NotFound
  assert router.from_href("/staff/organizations/unknown-id") == router.NotFound
  assert router.from_href("/q/") == router.NotFound
}

pub fn routes_have_canonical_paths_test() {
  assert router.to_path(router.SignIn) == "/sign-in"
  assert router.to_path(router.SignIn) != "/sign-out"
  assert router.to_path(router.QueueDashboard) == "/staff"
  assert router.to_path(router.OrganizationOverview) == "/staff/organization"
  assert router.to_path(router.StaffAccess) == "/staff/access"
  assert router.to_path(router.VisitorJoin) == "/visitor/join"
  assert router.to_path(router.PublicQueue("public-id")) == "/q/public-id"
  assert router.to_path(router.QueueSettings) == "/staff/settings"
  assert router.to_path(router.TicketPreview) == "/staff/ticket"
}

pub fn roundtrip_test() {
  [
    router.SignIn,
    router.QueueDashboard,
    router.VisitorJoin,
    router.PublicQueue("abc"),
    router.QueueSettings,
    router.TicketPreview,
    router.OrganizationOverview,
    router.StaffAccess,
  ]
  |> list.each(fn(route) {
    assert router.from_href(router.to_path(route)) == route
  })
}

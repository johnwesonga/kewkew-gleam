import client/router

pub fn parses_known_routes_test() {
  assert router.from_path("/") == router.SignIn
  assert router.from_path("/sign-in") == router.SignIn
  assert router.from_path("/staff") == router.QueueDashboard
  assert router.from_path("/staff/organization") == router.OrganizationOverview
  assert router.from_path("/staff/settings") == router.QueueSettings
  assert router.from_path("/staff/ticket") == router.TicketPreview
  assert router.from_path("/visitor/join") == router.VisitorJoin
}

pub fn unknown_paths_fall_back_to_not_found_test() {
  assert router.from_path("/unknown") == router.NotFound
  assert router.from_path("/staff/organizations/unknown-id") == router.NotFound
}

pub fn routes_have_canonical_paths_test() {
  assert router.to_path(router.SignIn) == "/sign-in"
  assert router.to_path(router.QueueDashboard) == "/staff"
  assert router.to_path(router.OrganizationOverview) == "/staff/organization"
  assert router.to_path(router.VisitorJoin) == "/visitor/join"
  assert router.to_path(router.QueueSettings) == "/staff/settings"
  assert router.to_path(router.TicketPreview) == "/staff/ticket"
}

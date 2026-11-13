import client/organization
import gleam/option.{Some}
import gleam/string
import lustre/element
import shared.{
  type LocationOverview, type MembershipRole, type OrganizationOverview, Admin,
  Location, LocationOverview, Operator, Organization, OrganizationOverview,
}

pub fn admin_without_locations_sees_the_next_setup_step_test() {
  let markup =
    overview(True, Admin, [])
    |> organization.overview_card(organization.init(), fn(_) { Nil }, Nil)
    |> element.to_string
  let assert True = string.contains(markup, "Start by creating a location")
  let assert True = string.contains(markup, "Create your first location")
}

pub fn operator_without_locations_is_not_shown_admin_setup_actions_test() {
  let markup =
    overview(False, Operator, [])
    |> organization.overview_card(organization.init(), fn(_) { Nil }, Nil)
    |> element.to_string
  let assert True = string.contains(markup, "No locations assigned")
  let assert True = string.contains(markup, "Ask an administrator")
  let assert False = string.contains(markup, "Start by creating a location")
  let assert False = string.contains(markup, "Create your first location")
}

pub fn admin_with_location_without_services_sees_the_next_step_test() {
  let markup =
    overview(True, Admin, [location_without_services()])
    |> organization.overview_card(organization.init(), fn(_) { Nil }, Nil)
    |> element.to_string
  let assert True = string.contains(markup, "Main Location")
  let assert True = string.contains(markup, "No services yet")
  let assert True = string.contains(markup, "configure a queue")
}

pub fn operator_with_location_does_not_receive_service_setup_instruction_test() {
  let markup =
    overview(False, Operator, [location_without_services()])
    |> organization.overview_card(organization.init(), fn(_) { Nil }, Nil)
    |> element.to_string
  let assert True = string.contains(markup, "No services are configured")
  let assert False = string.contains(markup, "Add a service")
}

pub fn administrator_organization_card_shows_name_editor_test() {
  let markup =
    organization.overview_card(
      overview(True, Admin, []),
      organization.init(),
      fn(_) { Nil },
      Nil,
    )
    |> element.to_string
  let assert True = string.contains(markup, "Organization name")
  let assert True = string.contains(markup, "Save name")
}

pub fn operator_organization_card_hides_name_editor_test() {
  let markup =
    organization.overview_card(
      overview(False, Operator, []),
      organization.init(),
      fn(_) { Nil },
      Nil,
    )
    |> element.to_string
  let assert False = string.contains(markup, "Organization name")
}

pub fn submitting_blank_organization_name_shows_validation_error_test() {
  let #(model, _) =
    organization.update(organization.init(), organization.Submit("org-1"))
  let assert Some(message) = model.error
  let assert True = string.contains(message, "Enter an organization name")
}

fn overview(
  can_manage: Bool,
  role: MembershipRole,
  locations: List(LocationOverview),
) -> OrganizationOverview {
  OrganizationOverview(
    organization: Organization(
      id: "org-1",
      name: "Example organization",
      created_at: "2026-11-12T00:00:00Z",
      updated_at: "2026-11-12T00:00:00Z",
    ),
    role:,
    can_manage:,
    locations:,
  )
}

fn location_without_services() -> LocationOverview {
  LocationOverview(
    location: Location(
      id: "location-1",
      organization_id: "org-1",
      name: "Main Location",
      timezone: "UTC",
      is_active: True,
      created_at: "2026-11-12T00:00:00Z",
      updated_at: "2026-11-12T00:00:00Z",
    ),
    services: [],
  )
}

import client/organization
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/element
import shared.{
  type LocationOverview, type MembershipRole, type OrganizationOverview,
  type Queue, type QueueSessionState, Admin, Anonymous, Closed, Location,
  LocationOverview, Open, Operator, Organization, OrganizationOverview, Paused,
  Queue, Service, ServiceOverview,
}

pub fn admin_without_locations_sees_the_next_setup_step_test() {
  let markup =
    overview(True, Admin, [])
    |> organization.overview_card(organization.init(), fn(message) { message })
    |> element.to_string
  let assert True = string.contains(markup, "Start by creating a location")
  let assert True = string.contains(markup, "Create your first location")
  let assert True = string.contains(markup, "Add location")
}

pub fn operator_without_locations_is_not_shown_admin_setup_actions_test() {
  let markup =
    overview(False, Operator, [])
    |> organization.overview_card(organization.init(), fn(message) { message })
    |> element.to_string
  let assert True = string.contains(markup, "No locations assigned")
  let assert True = string.contains(markup, "Ask an administrator")
  let assert False = string.contains(markup, "Start by creating a location")
  let assert False = string.contains(markup, "Create your first location")
  let assert False = string.contains(markup, "Add location")
}

pub fn admin_with_location_without_services_sees_the_next_step_test() {
  let markup =
    overview(True, Admin, [location_without_services()])
    |> organization.overview_card(organization.init(), fn(message) { message })
    |> element.to_string
  let assert True = string.contains(markup, "Main Location")
  let assert True = string.contains(markup, "No services yet")
  let assert True = string.contains(markup, "configure a queue")
  let assert True = string.contains(markup, "Edit location")
  let assert True = string.contains(markup, "Services at Main Location")
  let assert True = string.contains(markup, "location-services-panel")
  let assert True = string.contains(markup, "organization-locations-column")
  let assert True = string.contains(markup, "organization-services-row")
}

pub fn operator_with_location_does_not_receive_service_setup_instruction_test() {
  let markup =
    overview(False, Operator, [location_without_services()])
    |> organization.overview_card(organization.init(), fn(message) { message })
    |> element.to_string
  let assert True = string.contains(markup, "No services are configured")
  let assert False = string.contains(markup, "Add a service")
  let assert False = string.contains(markup, "Edit location")
}

pub fn administrator_sees_queue_configuration_and_session_states_test() {
  let markup =
    organization.overview_card(
      overview(True, Admin, [
        location_with_queues([
          queue("inactive", False, None),
          queue("no-session", True, None),
          queue("open", True, Some(Open)),
          queue("paused", True, Some(Paused)),
          queue("closed", True, Some(Closed)),
        ]),
      ]),
      organization.init(),
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Inactive")
  let assert True = string.contains(markup, "No session")
  let assert True = string.contains(markup, "Open")
  let assert True = string.contains(markup, "Paused")
  let assert True = string.contains(markup, "Closed")
  let assert True = string.contains(markup, "Set up a queue")
  let assert True = string.contains(markup, "Add queue")
  let assert True = string.contains(markup, "service-row-heading")
  let assert True = string.contains(markup, "queue-overview-list")
}

pub fn operator_sees_queue_states_without_queue_setup_controls_test() {
  let markup =
    organization.overview_card(
      overview(False, Operator, [
        location_with_queues([
          queue("open", True, Some(Open)),
        ]),
      ]),
      organization.init(),
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Open")
  let assert False = string.contains(markup, "Set up a queue")
  let assert False = string.contains(markup, "Edit")
}

pub fn administrator_can_open_location_creation_form_test() {
  let #(editor, _) =
    organization.update(organization.init(), organization.NewLocation("org-1"))
  let markup =
    organization.overview_card(overview(True, Admin, []), editor, fn(message) {
      message
    })
    |> element.to_string
  let assert True = string.contains(markup, "Location name")
  let assert True = string.contains(markup, "Timezone")
  let assert True = string.contains(markup, "<select")
  let assert True = string.contains(markup, "value=\"America/Los_Angeles\"")
  let assert True = string.contains(markup, "value=\"US/Mountain\"")
  let assert True = string.contains(markup, "Save location")
  let assert True = string.contains(markup, "class=\"quiet\"")
  let assert True = string.contains(markup, "location-form-actions")
}

pub fn administrator_can_open_location_creation_form_when_locations_exist_test() {
  let #(editor, _) =
    organization.update(organization.init(), organization.NewLocation("org-1"))
  let markup =
    organization.overview_card(
      overview(True, Admin, [location_without_services()]),
      editor,
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Location name")
  let assert True = string.contains(markup, "Save location")
}

pub fn submitting_location_without_a_name_shows_validation_error_test() {
  let #(editor, _) =
    organization.update(organization.init(), organization.NewLocation("org-1"))
  let #(editor, _) =
    organization.update(editor, organization.SaveLocation("org-1"))
  let assert Some(message) = editor.location_error
  let assert True = string.contains(message, "Enter a location name")
}

pub fn operator_location_card_has_no_location_edit_action_test() {
  let markup =
    organization.overview_card(
      overview(False, Operator, [location_without_services()]),
      organization.init(),
      fn(message) { message },
    )
    |> element.to_string
  let assert False = string.contains(markup, "Add location")
  let assert False = string.contains(markup, "Edit location")
  let assert False = string.contains(markup, "Add service")
}

pub fn administrator_can_create_service_at_a_location_test() {
  let #(editor, _) =
    organization.update(
      organization.init(),
      organization.NewService("location-1"),
    )
  let markup =
    organization.overview_card(
      overview(True, Admin, [location_without_services()]),
      editor,
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Service name")
  let assert True = string.contains(markup, "Service description")
  let assert True = string.contains(markup, "Save service")
  let assert True = string.contains(markup, "optional")
}

pub fn administrator_organization_card_shows_name_editor_test() {
  let markup =
    organization.overview_card(
      overview(True, Admin, []),
      organization.init(),
      fn(message) { message },
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
      fn(message) { message },
    )
    |> element.to_string
  let assert False = string.contains(markup, "Organization name")
}

pub fn submitting_blank_organization_name_shows_validation_error_test() {
  let #(model, _) =
    organization.update(organization.init(), organization.Submit("org-1", ""))
  let assert Some(message) = model.error
  let assert True = string.contains(message, "Enter an organization name")
}

pub fn submitting_displayed_organization_name_does_not_show_required_error_test() {
  let #(model, _) =
    organization.update(
      organization.init(),
      organization.Submit("org-1", "Current organization"),
    )
  let assert None = model.error
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

fn location_with_queues(queues: List(Queue)) -> LocationOverview {
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
    services: [
      ServiceOverview(
        service: Service(
          id: "service-1",
          organization_id: "org-1",
          location_id: "location-1",
          name: "Consultation",
          description: None,
          is_active: True,
          created_at: "2026-11-12T00:00:00Z",
          updated_at: "2026-11-12T00:00:00Z",
        ),
        queues:,
      ),
      ServiceOverview(
        service: Service(
          id: "service-empty",
          organization_id: "org-1",
          location_id: "location-1",
          name: "New Service",
          description: None,
          is_active: True,
          created_at: "2026-11-12T00:00:00Z",
          updated_at: "2026-11-12T00:00:00Z",
        ),
        queues: [],
      ),
    ],
  )
}

fn queue(
  name: String,
  is_active: Bool,
  current_session_state: Option(QueueSessionState),
) -> Queue {
  Queue(
    id: name,
    organization_id: "org-1",
    location_id: "location-1",
    service_id: "service-1",
    name:,
    identity_policy: Anonymous,
    active_ticket_capacity: None,
    is_active:,
    current_session_state:,
    public_id: None,
    created_at: "2026-11-12T00:00:00Z",
    updated_at: "2026-11-12T00:00:00Z",
  )
}

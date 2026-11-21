import client/organization
import client/staff_access
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import lustre/dev/simulate
import lustre/element
import lustre/element/html
import rsvp
import shared.{
  type LocationOverview, type MembershipRole, type OrganizationOverview,
  type Queue, type QueueSessionState, Admin, Anonymous, Closed, Location,
  LocationOverview, Open, Operator, Organization, OrganizationOverview, Paused,
  Queue, Sent, Service, ServiceOverview, StaffInvitation,
}
import shared/staff

pub fn organization_overview_does_not_render_staff_access_form_test() {
  let admin_markup =
    organization.overview_card(
      overview(True, Admin, [location_without_services()]),
      organization.init(),
      fn(message) { message },
    )
    |> element.to_string
  let operator_markup =
    organization.overview_card(
      overview(False, Operator, [location_without_services()]),
      organization.init(),
      fn(message) { message },
    )
    |> element.to_string
  let assert False = string.contains(admin_markup, "Invite a teammate")
  let assert False = string.contains(admin_markup, "Initial role")
  let assert False = string.contains(admin_markup, "Location access")
  let assert False = string.contains(operator_markup, "Invite a teammate")
  Nil
}

pub fn location_timezone_select_includes_utc_and_common_timezones_test() {
  let #(model, _) =
    organization.update(organization.init(), organization.NewLocation("org-1"))
  let markup =
    organization.overview_card(overview(True, Admin, []), model, fn(message) {
      message
    })
    |> element.to_string
  let assert True = string.contains(markup, "value=\"UTC\"")
  let assert True = string.contains(markup, "value=\"Europe/London\"")
  let assert True = string.contains(markup, "value=\"America/New_York\"")
  Nil
}

pub fn editing_location_retains_unlisted_timezone_as_selected_option_test() {
  let #(model, _) =
    organization.update(
      organization.init(),
      organization.EditLocation(
        "org-1",
        "location-1",
        "Main Location",
        "Asia/Kathmandu",
      ),
    )
  let markup =
    organization.overview_card(
      overview(True, Admin, [location_without_services()]),
      model,
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "value=\"Asia/Kathmandu\"")
  let assert True = string.contains(markup, "Asia/Kathmandu")
  let assert True = string.contains(markup, "selected")
  Nil
}

pub fn staff_access_view_uses_workspace_card_hierarchy_and_org_context_test() {
  let markup =
    staff_access.view(
      Some([overview(True, Admin, [location_without_services()])]),
      organization.init(),
      [],
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "staff-access-workspace")
  let assert True = string.contains(markup, "staff-access-overview card")
  let assert True = string.contains(markup, "Example organization")
  let assert True = string.contains(markup, "New invitation")
  Nil
}

pub fn staff_access_lists_sent_invitations_without_exposing_secrets_test() {
  let invitation =
    StaffInvitation(
      id: "invite-1",
      organization_id: "org-1",
      invited_email: "new.staff@example.com",
      role: Operator,
      location_ids: ["location-1"],
      created_by_user_id: "admin-1",
      created_at: "2026-11-16T10:00:00Z",
      expires_at: "2026-11-23T10:00:00Z",
      delivery_state: Sent,
      accepted_by_user_id: None,
      accepted_at: None,
      revoked_at: None,
    )
  let markup =
    staff_access.view(
      Some([overview(True, Admin, [location_without_services()])]),
      organization.init(),
      [invitation],
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Sent invitations")
  let assert True = string.contains(markup, "new.staff@example.com")
  let assert True = string.contains(markup, "Main Location")
  let assert True = string.contains(markup, "Expires")
  let assert True = string.contains(markup, "Sent")
  Nil
}

pub fn operator_location_check_state_satisfies_invitation_validation_test() {
  let model = organization.init()
  let #(model, _) =
    organization.update(
      model,
      organization.InviteEmailChanged("staff@example.com"),
    )
  let #(model, _) =
    organization.update(
      model,
      organization.InviteLocationChanged("location-1", True),
    )
  let assert ["location-1"] = model.invite_location_ids
  let assert "staff@example.com" = model.invite_email
  let #(model, _) =
    organization.update(model, organization.InviteStaff("org-1"))
  let assert None = model.invite_status
}

pub fn admin_without_locations_sees_the_next_setup_step_test() {
  let markup =
    overview(True, Admin, [])
    |> organization.overview_card(organization.init(), fn(message) { message })
    |> element.to_string
  let assert True = string.contains(markup, "Start by creating a location")
  let assert True = string.contains(markup, "Create your first location")
  let assert True = string.contains(markup, "Add a location")
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
  let assert False = string.contains(markup, "Add a location")
}

pub fn admin_with_location_without_services_sees_the_next_step_test() {
  let markup =
    overview(True, Admin, [location_without_services()])
    |> organization.overview_card(organization.init(), fn(message) { message })
    |> element.to_string
  let assert True = string.contains(markup, "Main Location")
  let assert True = string.contains(markup, "No services yet")
  let assert True = string.contains(markup, "configure a queue")
  let assert True = string.contains(markup, "organization-locations-heading")
  let assert True = string.contains(markup, "1 location")
  let assert True = string.contains(markup, "location-icon")
  let assert True = string.contains(markup, "Deactivate")
  let assert True = string.contains(markup, "Edit")
  let assert True = string.contains(markup, "Services by location")
  let assert True = string.contains(markup, "Main Location")
  let assert True = string.contains(markup, "0 services")
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
  let assert False = string.contains(markup, "location-action")
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
  let assert True = string.contains(markup, "service-row-actions")
  let assert True = string.contains(markup, "2 services")
  let assert True = string.contains(markup, "Active")
  let assert True = string.contains(markup, "Deactivate")
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
  let assert False = string.contains(markup, "Add a location")
  let assert False = string.contains(markup, "location-action")
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

pub fn administrator_can_toggle_service_availability_test() {
  let markup =
    organization.overview_card(
      overview(True, Admin, [location_with_queues([])]),
      organization.init(),
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Deactivate")
}

pub fn operator_cannot_toggle_service_availability_test() {
  let markup =
    organization.overview_card(
      overview(False, Operator, [location_with_queues([])]),
      organization.init(),
      fn(message) { message },
    )
    |> element.to_string
  let assert False = string.contains(markup, "Deactivate service")
  let assert False = string.contains(markup, "Reactivate service")
}

pub fn administrator_sees_location_availability_action_test() {
  let markup =
    organization.overview_card(
      overview(True, Admin, [location_without_services()]),
      organization.init(),
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Deactivate")
}

pub fn operator_does_not_see_location_availability_action_test() {
  let markup =
    organization.overview_card(
      overview(False, Operator, [location_without_services()]),
      organization.init(),
      fn(message) { message },
    )
    |> element.to_string
  let assert False = string.contains(markup, "Deactivate")
  let assert False = string.contains(markup, "Reactivate")
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
  let assert True = string.contains(markup, "Save changes")
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

pub fn staff_members_show_suspend_restore_and_role_to_administrators_test() {
  let #(editor, _) =
    organization.update(
      organization.init(),
      organization.MembersLoaded(
        "org-1",
        Ok([
          staff.Member(
            "org-1",
            "active",
            "Active Staff",
            "active@example.com",
            Operator,
            shared.Active,
          ),
          staff.Member(
            "org-1",
            "suspended",
            "Suspended Staff",
            "suspended@example.com",
            Admin,
            shared.Suspended,
          ),
        ]),
      ),
    )
  let markup =
    staff_access.view(Some([overview(True, Admin, [])]), editor, [], fn(_) {
      Nil
    })
    |> element.to_string
  let assert True = string.contains(markup, "Suspend access for Active Staff")
  let assert True =
    string.contains(markup, "Restore access for Suspended Staff")
  let assert True = string.contains(markup, "Suspended")
  let assert True = string.contains(markup, "Administrator")
  let restricted =
    staff_access.view(Some([overview(False, Operator, [])]), editor, [], fn(_) {
      Nil
    })
    |> element.to_string
  let assert False = string.contains(restricted, "Suspend access")
  let assert False = string.contains(restricted, "Restore access")
}

pub fn staff_status_update_reports_pending_success_and_last_admin_conflict_test() {
  let #(pending, _) =
    organization.update(
      organization.init(),
      organization.SetMemberActive("org-1", "user", False),
    )
  let assert True = pending.member_pending
  let #(suspended, _) =
    organization.update(
      pending,
      organization.MemberStatusSaved("org-1", False, Ok(Nil)),
    )
  let assert False = suspended.member_pending
  let assert Some("Staff access suspended.") = suspended.member_notice
  let #(restored, _) =
    organization.update(
      suspended,
      organization.MemberStatusSaved("org-1", True, Ok(Nil)),
    )
  let assert Some("Staff access restored.") = restored.member_notice
  let #(blocked, _) =
    organization.update(
      pending,
      organization.MemberStatusSaved(
        "org-1",
        False,
        Error(rsvp.HttpError(response.new(409) |> response.set_body("{}"))),
      ),
    )
  let assert Some(message) = blocked.member_notice
  let assert True = string.contains(message, "Another active administrator")
  let assert False = blocked.member_pending
}

pub fn staff_member_list_handles_empty_and_failed_loads_test() {
  let #(empty, _) =
    organization.update(
      organization.init(),
      organization.MembersLoaded("org-1", Ok([])),
    )
  let markup =
    staff_access.view(Some([overview(True, Admin, [])]), empty, [], fn(_) {
      Nil
    })
    |> element.to_string
  let assert True = string.contains(markup, "No staff members found")
  let #(failed, _) =
    organization.update(
      empty,
      organization.MembersLoaded("org-1", Error(rsvp.NetworkError)),
    )
  let assert Some(message) = failed.member_notice
  let assert True = string.contains(message, "Could not load staff members")
}

pub fn staff_contract_decodes_roles_and_rejects_unknown_status_test() {
  let body =
    "{\"organization_id\":\"org-1\",\"user_id\":\"user\",\"name\":\"Staff\",\"email\":\"staff@example.com\",\"role\":\"operator\",\"status\":\"suspended\"}"
  let assert Ok(member) = json.parse(body, staff.decoder())
  member.status |> should.equal(shared.Suspended)
  let assert Error(_) =
    json.parse(string.replace(body, "suspended", "unknown"), staff.decoder())
}

pub fn staff_status_handler_accepts_server_json_success_response_test() {
  list.each([False, True], fn(active) {
    let app =
      simulate.simple(
        fn(_) { organization.init() },
        fn(model, message) { organization.update(model, message).0 },
        fn(_) { html.text("") },
      )
      |> simulate.start(Nil)
    let model =
      app
      |> rsvp.simulate(
        response.new(200)
          |> response.set_header("content-type", "application/json")
          |> response.set_body("{}"),
        organization.member_status_handler("org-1", active),
      )
      |> simulate.model
    model.member_pending |> should.be_false
    model.member_notice
    |> should.equal(
      Some(case active {
        True -> "Staff access restored."
        False -> "Staff access suspended."
      }),
    )
  })
}

pub fn staff_status_handler_preserves_last_admin_conflict_response_test() {
  let app =
    simulate.simple(
      fn(_) { organization.init() },
      fn(model, message) { organization.update(model, message).0 },
      fn(_) { html.text("") },
    )
    |> simulate.start(Nil)
  let model =
    app
    |> rsvp.simulate(
      response.new(409)
        |> response.set_header("content-type", "application/json")
        |> response.set_body(
          "{\"error\":\"another active administrator is required\"}",
        ),
      organization.member_status_handler("org-1", False),
    )
    |> simulate.model
  let assert Some(message) = model.member_notice
  string.contains(message, "Another active administrator") |> should.be_true
}

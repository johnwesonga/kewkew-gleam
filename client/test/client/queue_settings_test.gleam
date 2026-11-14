import client/queue_settings
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import shared.{
  type LocationOverview, type OrganizationOverview, type Queue, Admin, Location,
  LocationOverview, NameRequired, Open, Operator, Organization,
  OrganizationOverview, Queue, Service, ServiceOverview,
}

pub fn administrator_queue_form_uses_services_from_the_selected_location_test() {
  let #(model, _) =
    queue_settings.update(
      queue_settings.init(),
      queue_settings.OrganizationChanged("org-1"),
    )
  let #(model, _) =
    queue_settings.update(model, queue_settings.LocationChanged("location-1"))
  let markup =
    queue_settings.view(model, Some([organization(True)]), fn(message) {
      message
    })
    |> element.to_string
  let assert True = string.contains(markup, "Consultation")
  let assert False = string.contains(markup, "Eastside service")
  let assert True = string.contains(markup, "Maximum active tickets")
  let assert True = string.contains(markup, "First and last name required")
}

pub fn queue_form_rejects_a_zero_capacity_before_sending_test() {
  let #(model, _) =
    queue_settings.update(
      queue_settings.init(),
      queue_settings.OrganizationChanged("org-1"),
    )
  let #(model, _) =
    queue_settings.update(model, queue_settings.LocationChanged("location-1"))
  let #(model, _) =
    queue_settings.update(model, queue_settings.ServiceChanged("service-1"))
  let #(model, _) =
    queue_settings.update(model, queue_settings.NameChanged("Morning line"))
  let #(model, _) =
    queue_settings.update(model, queue_settings.CapacityChanged("0"))
  let #(model, _) = queue_settings.update(model, queue_settings.Save)
  let assert Some(message) = model.error
  let assert True = string.contains(message, "positive whole number")
}

pub fn operators_do_not_receive_a_queue_creation_form_test() {
  let markup =
    queue_settings.view(
      queue_settings.init(),
      Some([organization(False)]),
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Administrator access required")
  let assert False = string.contains(markup, "Create queue")
}

pub fn administrator_can_open_an_existing_queue_for_editing_test() {
  let #(model, _) =
    queue_settings.update(
      queue_settings.init(),
      queue_settings.BeginEdit(
        "org-1",
        "location-1",
        "service-1",
        existing_queue(),
      ),
    )
  let markup =
    queue_settings.view(model, Some([organization(True)]), fn(message) {
      message
    })
    |> element.to_string
  let assert True = string.contains(markup, "Queue configuration")
  let assert True = string.contains(markup, "Queue details")
  let assert True = string.contains(markup, "Example organization")
  let assert True = string.contains(markup, "Consultation")
  let assert True = string.contains(markup, "Main")
  let assert True = string.contains(markup, "/q/public-queue-id")
  let assert True = string.contains(markup, "QR code preview will appear here")
  let assert True = string.contains(markup, "Public link and QR code")
  let assert True = string.contains(markup, "Back to queue settings")
  let assert False = string.contains(markup, "Existing queues")
  let assert True = string.contains(markup, "value=\"Morning consultation\"")
  let assert True = string.contains(markup, "value=\"5\"")
  let assert True = string.contains(markup, "First and last name required")
  let assert True = string.contains(markup, "Location and service are fixed")
  let assert True = string.contains(markup, "Save changes")
  let assert False = string.contains(markup, "Choose location")
  let assert False = string.contains(markup, "Choose service")
  let assert [details_before_qr, ..] = string.split(markup, "QR code")
  let assert True = string.contains(details_before_qr, "Active ticket capacity")
  let assert True =
    string.contains(details_before_qr, "Location and service are fixed")
}

pub fn editing_queue_validates_capacity_before_sending_test() {
  let #(model, _) =
    queue_settings.update(
      queue_settings.init(),
      queue_settings.BeginEdit(
        "org-1",
        "location-1",
        "service-1",
        existing_queue(),
      ),
    )
  let #(model, _) =
    queue_settings.update(model, queue_settings.CapacityChanged("0"))
  let #(model, _) = queue_settings.update(model, queue_settings.Save)
  let assert Some(message) = model.error
  let assert True = string.contains(message, "positive whole number")
}

fn existing_queue() -> Queue {
  Queue(
    id: "queue-1",
    organization_id: "org-1",
    location_id: "location-1",
    service_id: "service-1",
    name: "Morning consultation",
    identity_policy: NameRequired,
    active_ticket_capacity: Some(5),
    is_active: True,
    current_session_state: Some(Open),
    public_id: Some("public-queue-id"),
    created_at: "now",
    updated_at: "now",
  )
}

fn organization(can_manage: Bool) -> OrganizationOverview {
  OrganizationOverview(
    organization: Organization(
      id: "org-1",
      name: "Example organization",
      created_at: "now",
      updated_at: "now",
    ),
    role: case can_manage {
      True -> Admin
      False -> Operator
    },
    can_manage:,
    locations: [
      location("location-1", "Main", "service-1", "Consultation"),
      location("location-2", "Eastside", "service-2", "Eastside service"),
    ],
  )
}

fn location(
  id: String,
  name: String,
  service_id: String,
  service_name: String,
) -> LocationOverview {
  LocationOverview(
    location: Location(
      id:,
      organization_id: "org-1",
      name:,
      timezone: "UTC",
      is_active: True,
      created_at: "now",
      updated_at: "now",
    ),
    services: [
      ServiceOverview(
        service: Service(
          id: service_id,
          organization_id: "org-1",
          location_id: id,
          name: service_name,
          description: None,
          is_active: True,
          created_at: "now",
          updated_at: "now",
        ),
        queues: case service_id {
          "service-1" -> [existing_queue()]
          _ -> []
        },
      ),
    ],
  )
}

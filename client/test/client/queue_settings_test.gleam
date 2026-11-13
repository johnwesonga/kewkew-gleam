import client/queue_settings
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import shared.{
  type LocationOverview, type OrganizationOverview, Admin, Location,
  LocationOverview, Operator, Organization, OrganizationOverview, Service,
  ServiceOverview,
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
        queues: [],
      ),
    ],
  )
}

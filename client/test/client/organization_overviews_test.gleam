import client/organization
import client/organization_overviews
import gleam/option.{None, Some}
import shared.{
  type LocationOverview, type OrganizationOverview, Admin, Location,
  LocationOverview, Organization, OrganizationOverview, Service, ServiceOverview,
}

pub fn replace_refreshes_the_cached_overview_after_a_service_save_test() {
  let old = overview([])
  let updated =
    overview([
      LocationOverview(
        location: Location(
          id: "location-1",
          organization_id: "org-1",
          name: "Main",
          timezone: "UTC",
          is_active: True,
          created_at: "now",
          updated_at: "now",
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
              created_at: "now",
              updated_at: "now",
            ),
            queues: [],
          ),
        ],
      ),
    ])

  let assert Some(response_overview) =
    organization_overviews.from_message(organization.ServiceSaved(Ok(updated)))
  let assert Some([saved]) =
    organization_overviews.replace(Some([old]), response_overview)
  let assert [location] = saved.locations
  let assert [service] = location.services
  let assert "Consultation" = service.service.name
}

fn overview(locations: List(LocationOverview)) -> OrganizationOverview {
  OrganizationOverview(
    organization: Organization(
      id: "org-1",
      name: "Example",
      created_at: "now",
      updated_at: "now",
    ),
    role: Admin,
    can_manage: True,
    locations:,
  )
}

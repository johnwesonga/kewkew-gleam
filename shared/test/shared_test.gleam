import gleam/json
import gleam/option.{None, Some}
import gleeunit
import shared.{
  Admin, Anonymous, Location, LocationOverview, Organization,
  OrganizationOverview, Queue, Service, ServiceOverview,
}
import shared/json as shared_json

pub fn main() -> Nil {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn hello_world_test() {
  let name = "Joe"
  let greeting = "Hello, " <> name <> "!"

  assert greeting == "Hello, Joe!"
}

pub fn organization_overview_json_round_trips_test() {
  let overview =
    OrganizationOverview(
      organization: Organization(
        id: "org-1",
        name: "Example organization",
        created_at: "2026-11-12T00:00:00Z",
        updated_at: "2026-11-12T00:00:00Z",
      ),
      role: Admin,
      can_manage: True,
      locations: [
        LocationOverview(
          location: Location(
            id: "location-1",
            organization_id: "org-1",
            name: "Main",
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
                name: "Food support",
                description: None,
                is_active: True,
                created_at: "2026-11-12T00:00:00Z",
                updated_at: "2026-11-12T00:00:00Z",
              ),
              queues: [
                Queue(
                  id: "queue-1",
                  organization_id: "org-1",
                  location_id: "location-1",
                  service_id: "service-1",
                  name: "Main queue",
                  identity_policy: Anonymous,
                  active_ticket_capacity: None,
                  is_active: True,
                  public_id: Some("public-queue"),
                  created_at: "2026-11-12T00:00:00Z",
                  updated_at: "2026-11-12T00:00:00Z",
                ),
              ],
            ),
          ],
        ),
      ],
    )
  let encoded =
    overview |> shared_json.organization_overview_to_json |> json.to_string
  let assert Ok(decoded) =
    json.parse(encoded, using: shared_json.organization_overview_decoder())
  assert overview == decoded
}

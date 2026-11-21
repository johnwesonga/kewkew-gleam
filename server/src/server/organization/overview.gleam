import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import server/database/parrot
import server/database/query
import server/sql
import shared.{Location, Organization, Service}
import shared/json as shared_json
import sqlight

pub type OverviewError {
  DatabaseFailure(String)
}

/// Return the organization overview only when the user has an active membership.
/// Operators receive only locations explicitly assigned to their membership.
pub fn for_user(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
) -> Result(Option(String), OverviewError) {
  use roles <- result.try(
    parrot.query(
      connection,
      sql.get_active_membership_role(organization_id, user_id),
    )
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  case roles {
    [sql.GetActiveMembershipRole(role)] ->
      load_overview(connection, user_id, organization_id, role)
    _ -> Ok(None)
  }
}

/// Return every active organization membership for the signed-in user.
pub fn list_for_user(
  connection: sqlight.Connection,
  user_id: String,
) -> Result(List(String), OverviewError) {
  use ids <- result.try(list_active_organization_ids(connection, user_id))
  list.try_map(ids, fn(id) {
    case for_user(connection, user_id, id) {
      Ok(overview) -> Ok(overview)
      Error(error) -> Error(error)
    }
  })
  |> result.map(fn(overviews) {
    list.filter_map(overviews, fn(overview) {
      case overview {
        Some(value) -> Ok(value)
        None -> Error(Nil)
      }
    })
  })
}

fn list_active_organization_ids(
  connection: sqlight.Connection,
  user_id: String,
) -> Result(List(String), OverviewError) {
  parrot.query(connection, sql.list_active_organization_ids(user_id))
  |> result.map(fn(rows) {
    list.map(rows, fn(row) {
      let sql.ListActiveOrganizationIds(organization_id) = row
      organization_id
    })
  })
  |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) })
}

fn load_overview(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  role: String,
) -> Result(Option(String), OverviewError) {
  use organizations <- result.try(
    parrot.query(connection, sql.get_organization(organization_id))
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  case organizations {
    [sql.GetOrganization(id, name, created_at, updated_at)] -> {
      let organization = Organization(id:, name:, created_at:, updated_at:)
      let organization_json =
        shared_json.organization_to_json(organization)
        |> json.to_string
      use locations <- result.try(load_locations(
        connection,
        user_id,
        organization_id,
        role,
      ))
      let can_manage = case role {
        "admin" -> "true"
        _ -> "false"
      }
      let body =
        "{\"organization\":"
        <> organization_json
        <> ",\"role\":\""
        <> role
        <> "\",\"can_manage\":"
        <> can_manage
        <> ",\"locations\":["
        <> string.join(locations, ",")
        <> "]}"
      Ok(Some(body))
    }
    _ -> Ok(None)
  }
}

fn load_locations(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  role: String,
) -> Result(List(String), OverviewError) {
  use rows <- result.try(
    parrot.query(
      connection,
      sql.list_overview_locations(organization_id, role, user_id),
    )
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  list.try_map(rows, fn(row) {
    let sql.ListOverviewLocations(
      id,
      organization_id,
      name,
      timezone,
      is_active,
      created_at,
      updated_at,
    ) = row
    let location =
      Location(
        id:,
        organization_id:,
        name:,
        timezone:,
        is_active: is_active == 1,
        created_at:,
        updated_at:,
      )
    use services <- result.try(load_services(connection, organization_id, id))
    let location_json = shared_json.location_to_json(location) |> json.to_string
    Ok(
      "{\"location\":"
      <> location_json
      <> ",\"services\":["
      <> string.join(services, ",")
      <> "]}",
    )
  })
}

fn load_services(
  connection: sqlight.Connection,
  organization_id: String,
  location_id: String,
) -> Result(List(String), OverviewError) {
  use rows <- result.try(
    parrot.query(
      connection,
      sql.list_overview_services(organization_id, location_id),
    )
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  list.try_map(rows, fn(row) {
    let sql.ListOverviewServices(
      id,
      organization_id,
      location_id,
      name,
      description,
      is_active,
      created_at,
      updated_at,
    ) = row
    let service =
      Service(
        id:,
        organization_id:,
        location_id:,
        name:,
        description:,
        is_active: is_active == 1,
        created_at:,
        updated_at:,
      )
    use queues <- result.try(load_queues(
      connection,
      organization_id,
      location_id,
      id,
    ))
    let service_json = shared_json.service_to_json(service) |> json.to_string
    Ok(
      "{\"service\":"
      <> service_json
      <> ",\"queues\":["
      <> string.join(queues, ",")
      <> "]}",
    )
  })
}

fn load_queues(
  connection: sqlight.Connection,
  organization_id: String,
  location_id: String,
  service_id: String,
) -> Result(List(String), OverviewError) {
  use rows <- result.try(query.strings(
    connection,
    "SELECT json_object('id', id, 'organization_id', organization_id, 'location_id', location_id, 'service_id', service_id, 'name', name, 'identity_policy', identity_policy, 'active_ticket_capacity', active_ticket_capacity, 'is_active', json(CASE WHEN is_active = 1 THEN 'true' ELSE 'false' END), 'current_session_state', (SELECT state FROM queue_sessions WHERE organization_id = queues.organization_id AND queue_id = queues.id ORDER BY opened_at DESC, id DESC LIMIT 1), 'public_id', public_id, 'created_at', created_at, 'updated_at', updated_at) FROM queues WHERE organization_id = ? AND location_id = ? AND service_id = ? ORDER BY name",
    [
      sqlight.text(organization_id),
      sqlight.text(location_id),
      sqlight.text(service_id),
    ],
    DatabaseFailure,
  ))
  Ok(
    list.map(rows, fn(row) {
      let assert [queue_json] = row
      queue_json
    }),
  )
}

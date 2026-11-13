import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import server/database/query
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
  use roles <- result.try(query.strings(
    connection,
    "SELECT role FROM organization_memberships WHERE organization_id = ? AND user_id = ? AND status = 'active' LIMIT 1",
    [sqlight.text(organization_id), sqlight.text(user_id)],
    DatabaseFailure,
  ))
  case roles {
    [[role]] -> load_overview(connection, user_id, organization_id, role)
    _ -> Ok(None)
  }
}

/// Return every active organization membership for the signed-in user.
pub fn list_for_user(
  connection: sqlight.Connection,
  user_id: String,
) -> Result(List(String), OverviewError) {
  use rows <- result.try(query.strings(
    connection,
    "SELECT organization_id FROM organization_memberships WHERE user_id = ? AND status = 'active' ORDER BY organization_id",
    [sqlight.text(user_id)],
    DatabaseFailure,
  ))
  let ids =
    list.map(rows, fn(row) {
      let assert [id] = row
      id
    })
  list.try_map(ids, fn(id) {
    case for_user(connection, user_id, id) {
      Ok(Some(json)) -> Ok(json)
      Ok(None) -> Ok("null")
      Error(error) -> Error(error)
    }
  })
  |> result.map(fn(json_values) {
    list.filter(json_values, fn(json) { json != "null" })
  })
}

fn load_overview(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  role: String,
) -> Result(Option(String), OverviewError) {
  use organizations <- result.try(query.strings(
    connection,
    "SELECT json_object('id', id, 'name', name, 'created_at', created_at, 'updated_at', updated_at) FROM organizations WHERE id = ?",
    [sqlight.text(organization_id)],
    DatabaseFailure,
  ))
  case organizations {
    [[organization_json]] -> {
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
  use rows <- result.try(query.strings(
    connection,
    "SELECT id, json_object('id', id, 'organization_id', organization_id, 'name', name, 'timezone', timezone, 'is_active', json(CASE WHEN is_active = 1 THEN 'true' ELSE 'false' END), 'created_at', created_at, 'updated_at', updated_at) FROM locations WHERE organization_id = ? AND (? = 'admin' OR EXISTS (SELECT 1 FROM membership_location_access mla WHERE mla.organization_id = locations.organization_id AND mla.user_id = ? AND mla.location_id = locations.id)) ORDER BY name",
    [sqlight.text(organization_id), sqlight.text(role), sqlight.text(user_id)],
    DatabaseFailure,
  ))
  list.try_map(rows, fn(row) {
    let assert [location_id, location_json] = row
    use services <- result.try(load_services(
      connection,
      organization_id,
      location_id,
    ))
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
  use rows <- result.try(query.strings(
    connection,
    "SELECT id, json_object('id', id, 'organization_id', organization_id, 'location_id', location_id, 'name', name, 'description', description, 'is_active', json(CASE WHEN is_active = 1 THEN 'true' ELSE 'false' END), 'created_at', created_at, 'updated_at', updated_at) FROM services WHERE organization_id = ? AND location_id = ? ORDER BY name",
    [sqlight.text(organization_id), sqlight.text(location_id)],
    DatabaseFailure,
  ))
  list.try_map(rows, fn(row) {
    let assert [service_id, service_json] = row
    use queues <- result.try(load_queues(
      connection,
      organization_id,
      location_id,
      service_id,
    ))
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

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import server/database/parrot
import server/sql
import shared.{
  type IdentityPolicy, type QueueSessionState, Anonymous, Closed, Location,
  NameRequired, Open, Organization, Paused, Queue, Service,
}
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
    [row] -> load_overview(connection, user_id, organization_id, row.role)
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
  |> result.map(fn(rows) { list.map(rows, fn(row) { row.organization_id }) })
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
    [row] -> {
      let organization =
        Organization(
          id: row.id,
          name: row.name,
          created_at: row.created_at,
          updated_at: row.updated_at,
        )
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
    let location =
      Location(
        id: row.id,
        organization_id: row.organization_id,
        name: row.name,
        timezone: row.timezone,
        is_active: row.is_active == 1,
        created_at: row.created_at,
        updated_at: row.updated_at,
      )
    use services <- result.try(load_services(
      connection,
      row.organization_id,
      row.id,
    ))
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
    let service =
      Service(
        id: row.id,
        organization_id: row.organization_id,
        location_id: row.location_id,
        name: row.name,
        description: row.description,
        is_active: row.is_active == 1,
        created_at: row.created_at,
        updated_at: row.updated_at,
      )
    use queues <- result.try(load_queues(
      connection,
      row.organization_id,
      row.location_id,
      row.id,
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
  use rows <- result.try(
    parrot.query(
      connection,
      sql.list_overview_queues(organization_id, location_id, service_id),
    )
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  list.try_map(rows, fn(row) {
    use identity_policy <- result.try(identity_policy_from_string(
      row.identity_policy,
    ))
    use current_session_state <- result.try(case row.current_session_state {
      None -> Ok(None)
      Some(value) -> queue_session_state_from_string(value)
    })
    let queue =
      Queue(
        id: row.id,
        organization_id: row.organization_id,
        location_id: row.location_id,
        service_id: row.service_id,
        name: row.name,
        identity_policy:,
        active_ticket_capacity: row.active_ticket_capacity,
        is_active: row.is_active == 1,
        current_session_state:,
        public_id: row.public_id,
        created_at: row.created_at,
        updated_at: row.updated_at,
      )
    Ok(shared_json.queue_to_json(queue) |> json.to_string)
  })
}

fn identity_policy_from_string(
  value: String,
) -> Result(IdentityPolicy, OverviewError) {
  case value {
    "anonymous" -> Ok(Anonymous)
    "name_required" -> Ok(NameRequired)
    _ -> Error(DatabaseFailure("invalid queue identity policy: " <> value))
  }
}

fn queue_session_state_from_string(
  value: String,
) -> Result(Option(QueueSessionState), OverviewError) {
  case value {
    "open" -> Ok(Some(Open))
    "paused" -> Ok(Some(Paused))
    "closed" -> Ok(Some(Closed))
    _ -> Error(DatabaseFailure("invalid queue session state: " <> value))
  }
}

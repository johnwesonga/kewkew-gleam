import gleam/dynamic/decode
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import server/id
import server/organization/access
import sqlight

pub type QueueError {
  InvalidName
  InvalidIdentityPolicy
  InvalidCapacity
  QueueInactive
  LocationInactive
  ServiceInactive
  SessionAlreadyOpen
  QueueAccessForbidden
  NotFound
  Forbidden
  DatabaseFailure(String)
}

/// Create a queue at a service without opening an operating session.
pub fn create(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  location_id: String,
  service_id: String,
  name: String,
  identity_policy: String,
  active_ticket_capacity: Option(Int),
) -> Result(Nil, QueueError) {
  use #(name, identity_policy, active_ticket_capacity) <- result.try(validate(
    name,
    identity_policy,
    active_ticket_capacity,
  ))
  use _ <- result.try(access.require_admin(
    connection,
    user_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  case
    sqlight.query(
      "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, active_ticket_capacity, created_by_user_id, public_id) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM services WHERE id = ? AND organization_id = ? AND location_id = ?) RETURNING id",
      on: connection,
      with: [
        sqlight.text(id.new()),
        sqlight.text(organization_id),
        sqlight.text(location_id),
        sqlight.text(service_id),
        sqlight.text(name),
        sqlight.text(identity_policy),
        sqlight.nullable(sqlight.int, active_ticket_capacity),
        sqlight.text(user_id),
        sqlight.text(id.new()),
        sqlight.text(service_id),
        sqlight.text(organization_id),
        sqlight.text(location_id),
      ],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Update editable queue configuration without changing its service or session.
pub fn update(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
  name: String,
  identity_policy: String,
  active_ticket_capacity: Option(Int),
) -> Result(Nil, QueueError) {
  use #(name, identity_policy, active_ticket_capacity) <- result.try(validate(
    name,
    identity_policy,
    active_ticket_capacity,
  ))
  use _ <- result.try(access.require_admin(
    connection,
    user_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  case
    sqlight.query(
      "UPDATE queues SET name = ?, identity_policy = ?, active_ticket_capacity = ? WHERE id = ? AND organization_id = ? AND location_id = ? AND service_id = ? RETURNING id",
      on: connection,
      with: [
        sqlight.text(name),
        sqlight.text(identity_policy),
        sqlight.nullable(sqlight.int, active_ticket_capacity),
        sqlight.text(queue_id),
        sqlight.text(organization_id),
        sqlight.text(location_id),
        sqlight.text(service_id),
      ],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Change whether visitors may join a queue without changing its history.
pub fn set_active(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
  is_active: Bool,
) -> Result(Nil, QueueError) {
  use _ <- result.try(access.require_admin(
    connection,
    user_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  case
    sqlight.query(
      "UPDATE queues SET is_active = ? WHERE id = ? AND organization_id = ? AND location_id = ? AND service_id = ? RETURNING id",
      on: connection,
      with: [
        sqlight.bool(is_active),
        sqlight.text(queue_id),
        sqlight.text(organization_id),
        sqlight.text(location_id),
        sqlight.text(service_id),
      ],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Open a new operating session for authorized staff at an active queue.
pub fn open_session(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
) -> Result(Nil, QueueError) {
  use _ <- result.try(
    sqlight.exec("BEGIN IMMEDIATE", on: connection)
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  let opened = case
    openable_queue(
      connection,
      user_id,
      organization_id,
      location_id,
      service_id,
      queue_id,
    )
  {
    Error(error) -> Error(error)
    Ok(#(
      queue_active,
      location_active,
      service_active,
      role,
      location_assigned,
      session_state,
    )) ->
      case
        queue_active,
        location_active,
        service_active,
        role,
        location_assigned,
        session_state
      {
        0, _, _, _, _, _ -> Error(QueueInactive)
        _, 0, _, _, _, _ -> Error(LocationInactive)
        _, _, 0, _, _, _ -> Error(ServiceInactive)
        _, _, _, "operator", 0, _ -> Error(QueueAccessForbidden)
        _, _, _, _, _, Some("open") -> Error(SessionAlreadyOpen)
        _, _, _, _, _, Some("paused") -> Error(SessionAlreadyOpen)
        _, _, _, _, _, _ ->
          insert_session(connection, organization_id, queue_id)
      }
  }
  case opened {
    Ok(Nil) ->
      case sqlight.exec("COMMIT", on: connection) {
        Ok(Nil) -> Ok(Nil)
        Error(error) -> {
          let _ = sqlight.exec("ROLLBACK", on: connection)
          Error(DatabaseFailure(string.inspect(error)))
        }
      }
    Error(error) -> {
      let _ = sqlight.exec("ROLLBACK", on: connection)
      Error(error)
    }
  }
}

fn openable_queue(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
) -> Result(#(Int, Int, Int, String, Int, Option(String)), QueueError) {
  let decoder = {
    use queue_active <- decode.field(0, decode.int)
    use location_active <- decode.field(1, decode.int)
    use service_active <- decode.field(2, decode.int)
    use role <- decode.field(3, decode.string)
    use location_assigned <- decode.field(4, decode.int)
    use session_state <- decode.field(5, decode.optional(decode.string))
    decode.success(#(
      queue_active,
      location_active,
      service_active,
      role,
      location_assigned,
      session_state,
    ))
  }
  case
    sqlight.query(
      "SELECT queues.is_active, locations.is_active, services.is_active, organization_memberships.role, EXISTS (SELECT 1 FROM membership_location_access WHERE organization_id = queues.organization_id AND user_id = organization_memberships.user_id AND location_id = queues.location_id), (SELECT state FROM queue_sessions WHERE queue_id = queues.id ORDER BY opened_at DESC, id DESC LIMIT 1) FROM queues JOIN locations ON locations.id = queues.location_id AND locations.organization_id = queues.organization_id JOIN services ON services.id = queues.service_id AND services.organization_id = queues.organization_id AND services.location_id = queues.location_id JOIN organization_memberships ON organization_memberships.organization_id = queues.organization_id AND organization_memberships.user_id = ? AND organization_memberships.status = 'active' WHERE queues.id = ? AND queues.organization_id = ? AND queues.location_id = ? AND queues.service_id = ? LIMIT 1",
      on: connection,
      with: [
        sqlight.text(user_id),
        sqlight.text(queue_id),
        sqlight.text(organization_id),
        sqlight.text(location_id),
        sqlight.text(service_id),
      ],
      expecting: decoder,
    )
  {
    Ok([queue]) -> Ok(queue)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn insert_session(
  connection: sqlight.Connection,
  organization_id: String,
  queue_id: String,
) -> Result(Nil, QueueError) {
  case
    sqlight.query(
      "INSERT INTO queue_sessions (id, organization_id, queue_id, state) VALUES (?, ?, ?, 'open') RETURNING id",
      on: connection,
      with: [
        sqlight.text(id.new()),
        sqlight.text(organization_id),
        sqlight.text(queue_id),
      ],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(DatabaseFailure("queue session was not created"))
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn validate(
  name: String,
  identity_policy: String,
  active_ticket_capacity: Option(Int),
) -> Result(#(String, String, Option(Int)), QueueError) {
  let name = string.trim(name)
  case name {
    "" -> Error(InvalidName)
    _ ->
      case identity_policy {
        "anonymous" | "name_required" ->
          case active_ticket_capacity {
            Some(capacity) if capacity < 1 -> Error(InvalidCapacity)
            _ -> Ok(#(name, identity_policy, active_ticket_capacity))
          }
        _ -> Error(InvalidIdentityPolicy)
      }
  }
}

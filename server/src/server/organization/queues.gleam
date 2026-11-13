import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import server/organization/access
import sqlight

pub type QueueError {
  InvalidName
  InvalidIdentityPolicy
  InvalidCapacity
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
      "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, active_ticket_capacity, created_by_user_id) SELECT ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM services WHERE id = ? AND organization_id = ? AND location_id = ?) RETURNING id",
      on: connection,
      with: [
        sqlight.text(new_id()),
        sqlight.text(organization_id),
        sqlight.text(location_id),
        sqlight.text(service_id),
        sqlight.text(name),
        sqlight.text(identity_policy),
        sqlight.nullable(sqlight.int, active_ticket_capacity),
        sqlight.text(user_id),
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

fn new_id() -> String {
  crypto.strong_random_bytes(16)
  |> bit_array.base64_url_encode(False)
}

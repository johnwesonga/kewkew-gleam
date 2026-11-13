import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/result
import gleam/string
import gtz
import server/database/query
import sqlight
import zones

pub type LocationError {
  InvalidName
  InvalidTimezone
  NotFound
  Forbidden
  DatabaseFailure(String)
}

/// Create a location in an organization managed by the active administrator.
pub fn create(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  name: String,
  timezone: String,
) -> Result(Nil, LocationError) {
  use #(name, timezone) <- result.try(validate(name, timezone))
  use _ <- result.try(require_admin(connection, user_id, organization_id))
  case
    sqlight.query(
      "INSERT INTO locations (id, organization_id, name, timezone) SELECT ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM organization_memberships WHERE organization_id = ? AND user_id = ? AND role = 'admin' AND status = 'active') RETURNING id",
      on: connection,
      with: [
        sqlight.text(new_id()),
        sqlight.text(organization_id),
        sqlight.text(name),
        sqlight.text(timezone),
        sqlight.text(organization_id),
        sqlight.text(user_id),
      ],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(Forbidden)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Update a location's name and timezone without allowing organization moves.
pub fn update(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  location_id: String,
  name: String,
  timezone: String,
) -> Result(Nil, LocationError) {
  use #(name, timezone) <- result.try(validate(name, timezone))
  use _ <- result.try(require_admin(connection, user_id, organization_id))
  case
    sqlight.query(
      "UPDATE locations SET name = ?, timezone = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ? AND organization_id = ? AND EXISTS (SELECT 1 FROM organization_memberships WHERE organization_id = ? AND user_id = ? AND role = 'admin' AND status = 'active') RETURNING id",
      on: connection,
      with: [
        sqlight.text(name),
        sqlight.text(timezone),
        sqlight.text(location_id),
        sqlight.text(organization_id),
        sqlight.text(organization_id),
        sqlight.text(user_id),
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
  timezone: String,
) -> Result(#(String, String), LocationError) {
  let name = string.trim(name)
  let timezone = string.trim(timezone)
  case name, timezone {
    "", _ -> Error(InvalidName)
    _, "" -> Error(InvalidTimezone)
    _, _ ->
      case gtz.build_from(timezone, zones.database()) {
        Ok(_) -> Ok(#(name, timezone))
        Error(Nil) -> Error(InvalidTimezone)
      }
  }
}

fn require_admin(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
) -> Result(Nil, LocationError) {
  use roles <- result.try(query.strings(
    connection,
    "SELECT role FROM organization_memberships WHERE organization_id = ? AND user_id = ? AND status = 'active' LIMIT 1",
    [sqlight.text(organization_id), sqlight.text(user_id)],
    DatabaseFailure,
  ))
  case roles {
    [["admin"]] -> Ok(Nil)
    [[_]] -> Error(Forbidden)
    _ -> Error(NotFound)
  }
}

fn new_id() -> String {
  crypto.strong_random_bytes(16)
  |> bit_array.base64_url_encode(False)
}

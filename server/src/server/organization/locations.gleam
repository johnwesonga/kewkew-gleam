import gleam/dynamic/decode
import gleam/result
import gleam/string
import gtz
import server/database/parrot
import server/id
import server/organization/access
import server/sql
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
  use _ <- result.try(access.require_admin(
    connection,
    user_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  case
    parrot.query(
      connection,
      sql.create_location(
        id.new(),
        organization_id,
        name,
        timezone,
        organization_id,
        user_id,
      ),
    )
  {
    Ok([sql.CreateLocation(_)]) -> Ok(Nil)
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
  use _ <- result.try(access.require_admin(
    connection,
    user_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  case
    parrot.query(
      connection,
      sql.update_location(
        name,
        timezone,
        location_id,
        organization_id,
        organization_id,
        user_id,
      ),
    )
  {
    Ok([sql.UpdateLocation(_)]) -> Ok(Nil)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Change location availability without removing its services or history.
pub fn set_active(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  location_id: String,
  is_active: Bool,
) -> Result(Nil, LocationError) {
  use _ <- result.try(access.require_admin(
    connection,
    user_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  let active = case is_active {
    True -> 1
    False -> 0
  }
  case
    sqlight.query(
      "UPDATE locations SET is_active = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ? AND organization_id = ? RETURNING id",
      on: connection,
      with: [
        sqlight.int(active),
        sqlight.text(location_id),
        sqlight.text(organization_id),
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

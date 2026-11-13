import gleam/dynamic/decode
import gleam/result
import gleam/string
import server/organization/access
import sqlight

pub type UpdateError {
  NotFound
  Forbidden
  InvalidName
  DatabaseFailure(String)
}

/// Update an organization's display name for an active administrator.
pub fn update_name(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  name: String,
) -> Result(Nil, UpdateError) {
  let name = string.trim(name)
  case name {
    "" -> Error(InvalidName)
    _ -> {
      use _ <- result.try(access.require_admin(
        connection,
        user_id,
        organization_id,
        NotFound,
        Forbidden,
        DatabaseFailure,
      ))
      update_organization(connection, organization_id, name)
    }
  }
}

fn update_organization(
  connection: sqlight.Connection,
  organization_id: String,
  name: String,
) -> Result(Nil, UpdateError) {
  case
    sqlight.query(
      "UPDATE organizations SET name = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ? RETURNING id",
      on: connection,
      with: [sqlight.text(name), sqlight.text(organization_id)],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

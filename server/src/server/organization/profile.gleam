import gleam/result
import gleam/string
import server/database/parrot
import server/organization/access
import server/sql
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
    parrot.query(
      connection,
      sql.update_organization_name(name, organization_id),
    )
  {
    Ok([sql.UpdateOrganizationName(_)]) -> Ok(Nil)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

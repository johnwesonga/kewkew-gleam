import gleam/result
import gleam/string
import server/database/parrot
import server/database/query
import server/sql
import sqlight

/// Require an active administrator membership for an organization.
/// Error constructors are supplied by the calling feature module so its
/// existing public error type remains unchanged.
pub fn require_admin(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  not_found: error,
  forbidden: error,
  database_failure: fn(String) -> error,
) -> Result(Nil, error) {
  use roles <- result.try(
    parrot.query(
      connection,
      sql.get_active_membership_role(organization_id, user_id),
    )
    |> result.map_error(fn(error) { database_failure(string.inspect(error)) }),
  )
  case roles {
    [sql.GetActiveMembershipRole("admin")] -> Ok(Nil)
    [sql.GetActiveMembershipRole(_)] -> Error(forbidden)
    _ -> Error(not_found)
  }
}

/// Require any active membership, hiding organizations the user cannot see.
pub fn require_member(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  not_found: error,
  database_failure: fn(String) -> error,
) -> Result(Nil, error) {
  use memberships <- result.try(query.strings(
    connection,
    "SELECT user_id FROM organization_memberships WHERE organization_id = ? AND user_id = ? AND status = 'active' LIMIT 1",
    [sqlight.text(organization_id), sqlight.text(user_id)],
    database_failure,
  ))
  case memberships {
    [[_]] -> Ok(Nil)
    _ -> Error(not_found)
  }
}

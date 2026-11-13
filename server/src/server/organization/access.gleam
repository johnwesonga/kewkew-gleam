import gleam/result
import server/database/query
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
  use roles <- result.try(query.strings(
    connection,
    "SELECT role FROM organization_memberships WHERE organization_id = ? AND user_id = ? AND status = 'active' LIMIT 1",
    [sqlight.text(organization_id), sqlight.text(user_id)],
    database_failure,
  ))
  case roles {
    [["admin"]] -> Ok(Nil)
    [[_]] -> Error(forbidden)
    _ -> Error(not_found)
  }
}

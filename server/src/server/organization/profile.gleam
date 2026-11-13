import gleam/dynamic/decode
import gleam/result
import gleam/string
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
      use roles <- result.try(
        query_strings(
          connection,
          "SELECT role FROM organization_memberships WHERE organization_id = ? AND user_id = ? AND status = 'active' LIMIT 1",
          [sqlight.text(organization_id), sqlight.text(user_id)],
        ),
      )
      case roles {
        [["admin"]] -> update_organization(connection, organization_id, name)
        [[_]] -> Error(Forbidden)
        _ -> Error(NotFound)
      }
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

fn query_strings(
  connection: sqlight.Connection,
  query: String,
  parameters: List(sqlight.Value),
) -> Result(List(List(String)), UpdateError) {
  sqlight.query(
    query,
    on: connection,
    with: parameters,
    expecting: decode.list(decode.string),
  )
  |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) })
}

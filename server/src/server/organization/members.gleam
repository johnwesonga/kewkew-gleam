import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import server/database/parrot
import server/id
import server/organization/access
import server/sql
import sqlight

pub type MemberError {
  NotFound
  Forbidden
  InvalidAccess
  LastAdministrator
  DatabaseFailure(String)
}

pub fn list_members(
  connection: sqlight.Connection,
  actor: String,
  organization: String,
) -> Result(String, MemberError) {
  use _ <- result.try(access.require_admin(
    connection,
    actor,
    organization,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  use rows <- result.try(
    parrot.query(connection, sql.list_staff_members(organization))
    |> result.map_error(database_failure),
  )
  use assignments <- result.try(
    parrot.query(connection, sql.list_staff_assignments(organization))
    |> result.map_error(database_failure),
  )
  Ok(
    json.array(rows, fn(row) {
      json.object([
        #("organization_id", json.string(row.organization_id)),
        #("user_id", json.string(row.user_id)),
        #("name", json.string(row.name)),
        #("email", json.string(row.email)),
        #("role", json.string(row.role)),
        #("status", json.string(row.status)),
        #(
          "location_ids",
          json.array(
            assignments
              |> list.filter(fn(assignment) {
                assignment.user_id == row.user_id
              })
              |> list.map(fn(assignment) { assignment.location_id }),
            json.string,
          ),
        ),
      ])
    })
    |> json.to_string,
  )
}

/// SQLite's write lock serializes authorization, last-admin checks, and updates.
pub fn set_active(
  connection: sqlight.Connection,
  actor: String,
  organization: String,
  user: String,
  active: Bool,
) -> Result(Nil, MemberError) {
  transaction(connection, fn() {
    change_status(connection, actor, organization, user, active)
  })
}

fn transaction(
  connection: sqlight.Connection,
  run: fn() -> Result(Nil, MemberError),
) -> Result(Nil, MemberError) {
  use _ <- result.try(
    sqlight.exec("BEGIN IMMEDIATE", on: connection)
    |> result.map_error(database_failure),
  )
  let outcome = run()
  case outcome {
    Ok(Nil) ->
      case sqlight.exec("COMMIT", on: connection) {
        Ok(Nil) -> Ok(Nil)
        Error(error) -> {
          let _ = sqlight.exec("ROLLBACK", on: connection)
          Error(database_failure(error))
        }
      }
    Error(error) -> {
      let _ = sqlight.exec("ROLLBACK", on: connection)
      Error(error)
    }
  }
}

fn change_status(
  connection: sqlight.Connection,
  actor: String,
  organization: String,
  user: String,
  active: Bool,
) -> Result(Nil, MemberError) {
  use _ <- result.try(access.require_admin(
    connection,
    actor,
    organization,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  use rows <- result.try(
    parrot.query(connection, sql.get_staff_member(organization, user))
    |> result.map_error(database_failure),
  )
  use row <- result.try(case rows {
    [row] -> Ok(row)
    _ -> Error(NotFound)
  })
  let status = case active {
    True -> "active"
    False -> "suspended"
  }
  case row.status == status {
    True -> Ok(Nil)
    False -> {
      use _ <- result.try(case row.role, active {
        "admin", False ->
          protect_last_administrator(connection, organization, user)
        _, _ -> Ok(Nil)
      })
      use _ <- result.try(
        parrot.query(
          connection,
          sql.set_staff_member_status(status, organization, user),
        )
        |> result.map_error(database_failure),
      )
      use _ <- result.try(
        parrot.query(
          connection,
          sql.record_staff_status_change(
            id.new(),
            organization,
            actor,
            user,
            case active {
              True -> "reactivated"
              False -> "suspended"
            },
            Some(row.role),
            Some(row.status),
            Some(status),
          ),
        )
        |> result.map_error(database_failure),
      )
      Ok(Nil)
    }
  }
}

/// Call inside a write transaction before removing active administrator access.
pub fn protect_last_administrator(
  connection: sqlight.Connection,
  organization: String,
  user: String,
) -> Result(Nil, MemberError) {
  use rows <- result.try(
    parrot.query(connection, sql.get_staff_member(organization, user))
    |> result.map_error(database_failure),
  )
  case rows {
    [sql.GetStaffMember("admin", "active")] -> {
      use counts <- result.try(
        parrot.query(connection, sql.count_active_administrators(organization))
        |> result.map_error(database_failure),
      )
      case counts {
        [sql.CountActiveAdministrators(count)] if count > 1 -> Ok(Nil)
        _ -> Error(LastAdministrator)
      }
    }
    _ -> Ok(Nil)
  }
}

fn database_failure(error: sqlight.Error) -> MemberError {
  DatabaseFailure(string.inspect(error))
}

/// Change access without activating a suspended membership. All checks and writes
/// share the same write transaction as suspension and last-administrator checks.
pub fn update_access(
  connection: sqlight.Connection,
  actor: String,
  organization: String,
  user: String,
  role: String,
  location_ids: List(String),
) -> Result(Nil, MemberError) {
  transaction(connection, fn() {
    use _ <- result.try(access.require_admin(
      connection,
      actor,
      organization,
      NotFound,
      Forbidden,
      DatabaseFailure,
    ))
    use rows <- result.try(
      parrot.query(connection, sql.get_staff_member(organization, user))
      |> result.map_error(database_failure),
    )
    use member <- result.try(case rows {
      [member] -> Ok(member)
      _ -> Error(NotFound)
    })
    use ids <- result.try(case role {
      "admin" -> Ok([])
      "operator" if location_ids != [] -> Ok(list.unique(location_ids))
      _ -> Error(InvalidAccess)
    })
    use _ <- result.try(
      list.try_map(ids, fn(location_id) {
        case
          parrot.query(
            connection,
            sql.count_invitation_location(organization, location_id),
          )
        {
          Ok([sql.CountInvitationLocation(1)]) -> Ok(Nil)
          Ok(_) -> Error(InvalidAccess)
          Error(error) -> Error(database_failure(error))
        }
      }),
    )
    use _ <- result.try(case role {
      "operator" -> protect_last_administrator(connection, organization, user)
      _ -> Ok(Nil)
    })
    use _ <- result.try(
      parrot.query(connection, sql.update_staff_role(role, organization, user))
      |> result.map_error(database_failure),
    )
    use _ <- result.try(
      parrot.query(
        connection,
        sql.clear_invitee_location_access(organization, user),
      )
      |> result.map_error(database_failure),
    )
    use _ <- result.try(
      list.try_map(ids, fn(location_id) {
        parrot.query(
          connection,
          sql.assign_invited_location(organization, user, location_id),
        )
        |> result.map_error(database_failure)
      }),
    )
    use _ <- result.try(
      parrot.query(
        connection,
        sql.record_staff_access_change(
          id.new(),
          organization,
          actor,
          user,
          case member.role == role {
            True -> "location_access_changed"
            False -> "role_changed"
          },
          member.role,
          role,
          member.status,
          json.object([#("location_ids", json.array(ids, json.string))])
            |> json.to_string,
        ),
      )
      |> result.map_error(database_failure),
    )
    Ok(Nil)
  })
}

import gleam/json
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
  Ok(
    json.array(rows, fn(row) {
      json.object([
        #("organization_id", json.string(row.organization_id)),
        #("user_id", json.string(row.user_id)),
        #("name", json.string(row.name)),
        #("email", json.string(row.email)),
        #("role", json.string(row.role)),
        #("status", json.string(row.status)),
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
  use _ <- result.try(
    sqlight.exec("BEGIN IMMEDIATE", on: connection)
    |> result.map_error(database_failure),
  )
  let outcome = change_status(connection, actor, organization, user, active)
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

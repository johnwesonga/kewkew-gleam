import argus
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import server/database.{type DatabaseError, SchemaUnavailable, SqliteFailure}
import server/id
import sqlight

pub type Details {
  Details(
    organization_name: String,
    location_name: String,
    admin_name: String,
    email: String,
    password: String,
    timezone: String,
  )
}

pub type BootstrapResult {
  BootstrapResult(
    organization_id: String,
    location_id: String,
    administrator_id: String,
  )
}

pub type ValidationError {
  OrganizationNameRequired
  LocationNameRequired
  AdministratorNameRequired
  InvalidEmail
  PasswordTooShort
  PasswordTooLong
  TimezoneRequired
}

pub type BootstrapError {
  InvalidDetails(ValidationError)
  AlreadyInitialized
  PasswordHashFailed
  DatabaseFailed(DatabaseError)
}

/// Validate and atomically create the first organization, location,
/// administrator identity, credential, membership, and audit event.
pub fn create(
  connection: sqlight.Connection,
  details: Details,
) -> Result(BootstrapResult, BootstrapError) {
  use details <- result.try(
    validate(details) |> result.map_error(InvalidDetails),
  )
  use password_hash <- result.try(hash_password(details.password))
  run_transaction(connection, details, password_hash)
}

/// Normalize user-provided bootstrap details before touching persistence.
pub fn validate(details: Details) -> Result(Details, ValidationError) {
  let organization_name = string.trim(details.organization_name)
  let location_name = string.trim(details.location_name)
  let admin_name = string.trim(details.admin_name)
  let email = details.email |> string.trim |> string.lowercase
  let timezone = string.trim(details.timezone)

  case
    organization_name,
    location_name,
    admin_name,
    valid_email(email),
    string.length(details.password),
    timezone
  {
    "", _, _, _, _, _ -> Error(OrganizationNameRequired)
    _, "", _, _, _, _ -> Error(LocationNameRequired)
    _, _, "", _, _, _ -> Error(AdministratorNameRequired)
    _, _, _, False, _, _ -> Error(InvalidEmail)
    _, _, _, _, length, _ if length < 12 -> Error(PasswordTooShort)
    _, _, _, _, length, _ if length > 128 -> Error(PasswordTooLong)
    _, _, _, _, _, "" -> Error(TimezoneRequired)
    _, _, _, _, _, _ ->
      Ok(Details(
        organization_name:,
        location_name:,
        admin_name:,
        email:,
        password: details.password,
        timezone:,
      ))
  }
}

fn valid_email(email: String) -> Bool {
  case string.split(email, "@") {
    [local, domain] -> {
      let domain_parts = string.split(domain, ".")
      string.length(local) > 0
      && list.length(domain_parts) >= 2
      && list.all(domain_parts, fn(part) { string.length(part) > 0 })
    }
    _ -> False
  }
}

fn hash_password(password: String) -> Result(String, BootstrapError) {
  case argus.hash(argus.hasher(), password) {
    Ok(output) -> Ok(output.encoded_hash)
    Error(_) -> Error(PasswordHashFailed)
  }
}

fn run_transaction(
  connection: sqlight.Connection,
  details: Details,
  password_hash: String,
) -> Result(BootstrapResult, BootstrapError) {
  use _ <- result.try(
    sqlight.exec("BEGIN IMMEDIATE", on: connection)
    |> result.map_error(fn(error) { DatabaseFailed(SqliteFailure(error)) }),
  )

  case create_rows(connection, details, password_hash) {
    Ok(created) ->
      case sqlight.exec("COMMIT", on: connection) {
        Ok(Nil) -> Ok(created)
        Error(error) -> {
          let _ = sqlight.exec("ROLLBACK", on: connection)
          Error(DatabaseFailed(SqliteFailure(error)))
        }
      }
    Error(error) -> {
      let _ = sqlight.exec("ROLLBACK", on: connection)
      Error(error)
    }
  }
}

fn create_rows(
  connection: sqlight.Connection,
  details: Details,
  password_hash: String,
) -> Result(BootstrapResult, BootstrapError) {
  use initialized <- result.try(is_initialized(connection))
  case initialized {
    True -> Error(AlreadyInitialized)
    False -> {
      let organization_id = id.new()
      let location_id = id.new()
      let user_id = id.new()
      let account_id = id.new()
      let audit_id = id.new()

      use _ <- result.try(
        insert_one(
          "INSERT INTO organizations (id, name) VALUES (?, ?) RETURNING id",
          connection,
          [
            sqlight.text(organization_id),
            sqlight.text(details.organization_name),
          ],
        ),
      )
      use _ <- result.try(
        insert_one(
          "INSERT INTO locations (id, organization_id, name, timezone) VALUES (?, ?, ?, ?) RETURNING id",
          connection,
          [
            sqlight.text(location_id),
            sqlight.text(organization_id),
            sqlight.text(details.location_name),
            sqlight.text(details.timezone),
          ],
        ),
      )
      use _ <- result.try(
        insert_one(
          "INSERT INTO users (id, name, email, email_verified) VALUES (?, ?, ?, 0) RETURNING id",
          connection,
          [
            sqlight.text(user_id),
            sqlight.text(details.admin_name),
            sqlight.text(details.email),
          ],
        ),
      )
      use _ <- result.try(
        insert_one(
          "INSERT INTO accounts (id, account_id, provider_id, user_id, password, created_at, updated_at) VALUES (?, ?, 'credential', ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) RETURNING id",
          connection,
          [
            sqlight.text(account_id),
            sqlight.text(user_id),
            sqlight.text(user_id),
            sqlight.text(password_hash),
          ],
        ),
      )
      use _ <- result.try(
        insert_one(
          "INSERT INTO organization_memberships (organization_id, user_id, role, status) VALUES (?, ?, 'admin', 'active') RETURNING user_id",
          connection,
          [sqlight.text(organization_id), sqlight.text(user_id)],
        ),
      )
      use _ <- result.try(
        insert_one(
          "INSERT INTO membership_audit_events (id, organization_id, actor_user_id, subject_user_id, change_type, after_role, after_status) VALUES (?, ?, ?, ?, 'membership_created', 'admin', 'active') RETURNING id",
          connection,
          [
            sqlight.text(audit_id),
            sqlight.text(organization_id),
            sqlight.text(user_id),
            sqlight.text(user_id),
          ],
        ),
      )
      use _ <- result.try(update_setup_marker(connection, organization_id))

      Ok(BootstrapResult(
        organization_id:,
        location_id:,
        administrator_id: user_id,
      ))
    }
  }
}

fn is_initialized(
  connection: sqlight.Connection,
) -> Result(Bool, BootstrapError) {
  use setup_rows <- result.try(
    sqlight.query(
      "SELECT initialized_at FROM installation_setup WHERE id = 1",
      on: connection,
      with: [],
      expecting: decode.list(decode.optional(decode.string)),
    )
    |> result.map_error(fn(error) { DatabaseFailed(SqliteFailure(error)) }),
  )

  case setup_rows {
    [[Some(_)]] -> Ok(True)
    [[None]] -> {
      use organization_count <- result.try(count_rows(
        connection,
        "organizations",
      ))
      use user_count <- result.try(count_rows(connection, "users"))
      Ok(organization_count > 0 || user_count > 0)
    }
    _ -> Error(DatabaseFailed(SchemaUnavailable))
  }
}

fn count_rows(
  connection: sqlight.Connection,
  table: String,
) -> Result(Int, BootstrapError) {
  let sql = "SELECT COUNT(*) FROM " <> table
  case
    sqlight.query(
      sql,
      on: connection,
      with: [],
      expecting: decode.list(decode.int),
    )
  {
    Ok([[count]]) -> Ok(count)
    Ok(_) -> Error(DatabaseFailed(SchemaUnavailable))
    Error(error) -> Error(DatabaseFailed(SqliteFailure(error)))
  }
}

fn insert_one(
  sql: String,
  connection: sqlight.Connection,
  parameters: List(sqlight.Value),
) -> Result(Nil, BootstrapError) {
  case
    sqlight.query(
      sql,
      on: connection,
      with: parameters,
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(DatabaseFailed(SchemaUnavailable))
    Error(error) -> Error(DatabaseFailed(SqliteFailure(error)))
  }
}

fn update_setup_marker(
  connection: sqlight.Connection,
  organization_id: String,
) -> Result(Nil, BootstrapError) {
  case
    sqlight.query(
      "UPDATE installation_setup SET initialized_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), organization_id = ? WHERE id = 1 AND initialized_at IS NULL RETURNING id",
      on: connection,
      with: [sqlight.text(organization_id)],
      expecting: decode.list(decode.int),
    )
  {
    Ok([[1]]) -> Ok(Nil)
    Ok(_) -> Error(AlreadyInitialized)
    Error(error) -> Error(DatabaseFailed(SqliteFailure(error)))
  }
}

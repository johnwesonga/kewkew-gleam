import argus
import gleam/dynamic/decode
import gleam/option.{None, Some}
import server/database
import server/organization/bootstrap
import simplifile
import sqlight

pub fn creates_first_organization_location_and_admin_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, valid_details())

    let assert Ok([[1]]) = count(connection, "organizations")
    let assert Ok([[1]]) = count(connection, "locations")
    let assert Ok([[1]]) = count(connection, "users")
    let assert Ok([[1]]) = count(connection, "accounts")
    let assert Ok([[1]]) = count(connection, "organization_memberships")
    let assert Ok([[1]]) = count(connection, "membership_audit_events")
    let assert Ok([[Some(_)]]) =
      sqlight.query(
        "SELECT initialized_at FROM installation_setup WHERE id = 1 AND organization_id = ?",
        on: connection,
        with: [sqlight.text(created.organization_id)],
        expecting: decode.list(decode.optional(decode.string)),
      )
    let assert Ok([["Main"]]) =
      sqlight.query(
        "SELECT name FROM locations WHERE id = ?",
        on: connection,
        with: [sqlight.text(created.location_id)],
        expecting: decode.list(decode.string),
      )
    let assert Ok([["UTC"]]) =
      sqlight.query(
        "SELECT timezone FROM locations WHERE id = ?",
        on: connection,
        with: [sqlight.text(created.location_id)],
        expecting: decode.list(decode.string),
      )
    let assert Ok([["admin"]]) =
      sqlight.query(
        "SELECT role FROM organization_memberships WHERE organization_id = ? AND user_id = ?",
        on: connection,
        with: [
          sqlight.text(created.organization_id),
          sqlight.text(created.administrator_id),
        ],
        expecting: decode.list(decode.string),
      )
    let assert Ok([["active"]]) =
      sqlight.query(
        "SELECT status FROM organization_memberships WHERE organization_id = ? AND user_id = ?",
        on: connection,
        with: [
          sqlight.text(created.organization_id),
          sqlight.text(created.administrator_id),
        ],
        expecting: decode.list(decode.string),
      )
    let assert Ok([[password_hash]]) =
      sqlight.query(
        "SELECT password FROM accounts WHERE user_id = ?",
        on: connection,
        with: [sqlight.text(created.administrator_id)],
        expecting: decode.list(decode.string),
      )
    let assert Ok(verified) =
      argus.verify(password_hash, "correct horse battery staple")
    let assert True = verified
    Nil
  })
}

pub fn refuses_repeated_bootstrap_without_creating_more_records_test() {
  with_database(fn(connection) {
    let assert Ok(_) = bootstrap.create(connection, valid_details())
    let assert Error(bootstrap.AlreadyInitialized) =
      bootstrap.create(connection, valid_details())
    let assert Ok([[1]]) = count(connection, "organizations")
    let assert Ok([[1]]) = count(connection, "locations")
    let assert Ok([[1]]) = count(connection, "users")
    Nil
  })
}

pub fn rejects_invalid_details_before_writing_any_records_test() {
  with_database(fn(connection) {
    let details =
      bootstrap.Details(
        organization_name: " ",
        location_name: "Main",
        admin_name: "Admin",
        email: "not-an-email",
        password: "short",
        timezone: "UTC",
      )
    let assert Error(bootstrap.InvalidDetails(
      bootstrap.OrganizationNameRequired,
    )) = bootstrap.create(connection, details)
    let assert Ok([[0]]) = count(connection, "organizations")
    let assert Ok([[0]]) = count(connection, "locations")
    let assert Ok([[0]]) = count(connection, "users")
    Nil
  })
}

pub fn rolls_back_every_record_when_a_membership_insert_fails_test() {
  with_database(fn(connection) {
    let assert Ok(Nil) =
      sqlight.exec(
        "CREATE TRIGGER reject_admin_membership BEFORE INSERT ON organization_memberships BEGIN SELECT RAISE(ABORT, 'forced failure'); END",
        on: connection,
      )
    let assert Error(bootstrap.DatabaseFailed(_)) =
      bootstrap.create(connection, valid_details())
    let assert Ok([[0]]) = count(connection, "organizations")
    let assert Ok([[0]]) = count(connection, "locations")
    let assert Ok([[0]]) = count(connection, "users")
    let assert Ok([[0]]) = count(connection, "accounts")
    let assert Ok([[0]]) = count(connection, "organization_memberships")
    let assert Ok([[None]]) =
      sqlight.query(
        "SELECT initialized_at FROM installation_setup WHERE id = 1",
        on: connection,
        with: [],
        expecting: decode.list(decode.optional(decode.string)),
      )
    Nil
  })
}

fn with_database(run: fn(sqlight.Connection) -> Nil) -> Nil {
  let assert Ok(connection) = sqlight.open(":memory:")
  let assert Ok(schema) = simplifile.read("db/database.sql")
  let assert Ok(Nil) = database.initialize(connection, schema)
  run(connection)
  let _ = sqlight.close(connection)
  Nil
}

fn count(
  connection: sqlight.Connection,
  table: String,
) -> Result(List(List(Int)), sqlight.Error) {
  sqlight.query(
    "SELECT COUNT(*) FROM " <> table,
    on: connection,
    with: [],
    expecting: decode.list(decode.int),
  )
}

fn valid_details() -> bootstrap.Details {
  bootstrap.Details(
    organization_name: " Kewkew Test ",
    location_name: " Main ",
    admin_name: " Test Admin ",
    email: " ADMIN@EXAMPLE.COM ",
    password: "correct horse battery staple",
    timezone: " UTC ",
  )
}

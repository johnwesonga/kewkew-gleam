import gleam/dynamic/decode
import gleam/string
import server/database
import simplifile
import sqlight

fn legacy_database() -> #(sqlight.Connection, String) {
  let assert Ok(schema) = simplifile.read("db/database.sql")
  let legacy =
    string.replace(
      schema,
      "delivery_state IN ('pending', 'sent', 'failed')",
      "delivery_state IN ('sent', 'failed')",
    )
  let assert Ok(connection) = sqlight.open(":memory:")
  let assert Ok(Nil) = sqlight.exec(legacy, on: connection)
  let assert Ok(Nil) =
    sqlight.exec(
      "PRAGMA user_version = 1; INSERT INTO users (id,name,email) VALUES ('admin','Admin','admin@example.com'); INSERT INTO organizations (id,name) VALUES ('org','Organization'); INSERT INTO organization_memberships (organization_id,user_id,role,status) VALUES ('org','admin','admin','active'); INSERT INTO staff_invitations (id,organization_id,invited_email,role,location_ids_json,token_digest,created_by_user_id,created_at,expires_at,delivery_state) VALUES ('invite','org','invitee@example.com','admin','[]','legacy-digest','admin','2026-01-01T00:00:00Z','2030-01-01T00:00:00Z','sent');",
      on: connection,
    )
  #(connection, schema)
}

pub fn legacy_invitations_are_preserved_and_pending_delivery_is_enabled_test() {
  let #(connection, schema) = legacy_database()
  let assert Ok(Nil) = database.initialize(connection, schema)
  let assert Ok([["legacy-digest", "sent", "invitee@example.com"]]) =
    sqlight.query(
      "SELECT token_digest,delivery_state,invited_email FROM staff_invitations WHERE id = 'invite'",
      on: connection,
      with: [],
      expecting: decode.list(decode.string),
    )
  let assert Ok(Nil) =
    sqlight.exec(
      "UPDATE staff_invitations SET delivery_state = 'pending' WHERE id = 'invite'",
      on: connection,
    )
  let assert Error(_) =
    sqlight.exec(
      "UPDATE staff_invitations SET token_digest = 'changed' WHERE id = 'invite'",
      on: connection,
    )
  let assert Error(_) =
    sqlight.exec(
      "INSERT INTO staff_invitations (id,organization_id,invited_email,role,location_ids_json,token_digest,created_by_user_id,created_at,expires_at,delivery_state) VALUES ('duplicate','org','invitee@example.com','admin','[]','other-digest','admin','2026-01-01','2030-01-01','pending')",
      on: connection,
    )
  let assert Ok(Nil) = database.initialize(connection, schema)
  let assert Ok([["pending"]]) =
    sqlight.query(
      "SELECT delivery_state FROM staff_invitations",
      on: connection,
      with: [],
      expecting: decode.list(decode.string),
    )
  let assert Ok([[2]]) =
    sqlight.query(
      "PRAGMA user_version",
      on: connection,
      with: [],
      expecting: decode.list(decode.int),
    )
  let assert Ok([]) =
    sqlight.query(
      "PRAGMA foreign_key_check",
      on: connection,
      with: [],
      expecting: decode.dynamic,
    )
  let _ = sqlight.close(connection)
  Nil
}

pub fn migration_failure_rolls_back_table_and_version_test() {
  let #(connection, schema) = legacy_database()
  let assert Ok(Nil) =
    sqlight.exec("CREATE TABLE staff_invitations_v2 (id TEXT)", on: connection)
  let assert Error(_) = database.initialize(connection, schema)
  let assert Ok([["legacy-digest"]]) =
    sqlight.query(
      "SELECT token_digest FROM staff_invitations WHERE id = 'invite'",
      on: connection,
      with: [],
      expecting: decode.list(decode.string),
    )
  let assert Ok([[1]]) =
    sqlight.query(
      "PRAGMA user_version",
      on: connection,
      with: [],
      expecting: decode.list(decode.int),
    )
  let assert Ok(Nil) =
    sqlight.exec("DROP TABLE staff_invitations_v2", on: connection)
  let assert Ok(Nil) = database.initialize(connection, schema)
  let _ = sqlight.close(connection)
  Nil
}

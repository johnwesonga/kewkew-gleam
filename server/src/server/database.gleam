import gleam/dynamic/decode
import gleam/result
import simplifile
import sqlight

pub type DatabaseError {
  SqliteFailure(sqlight.Error)
  SchemaUnavailable
  SchemaReadFailed(path: String, reason: simplifile.FileError)
}

/// Open the database file, create its schema if it is new, and seed the
/// singleton setup marker used to make bootstrap one-time.
pub fn open(
  path: String,
  schema_path: String,
) -> Result(sqlight.Connection, DatabaseError) {
  use schema <- result.try(
    simplifile.read(schema_path)
    |> result.map_error(SchemaReadFailed(schema_path, _)),
  )

  use connection <- result.try(
    sqlight.open(path) |> result.map_error(SqliteFailure),
  )

  case initialize(connection, schema) {
    Ok(Nil) -> Ok(connection)
    Error(error) -> {
      let _ = sqlight.close(connection)
      Error(error)
    }
  }
}

/// Initialize a connection. This is public so tests can use isolated
/// in-memory SQLite databases.
pub fn initialize(
  connection: sqlight.Connection,
  schema: String,
) -> Result(Nil, DatabaseError) {
  use _ <- result.try(
    sqlight.exec("PRAGMA foreign_keys = ON", on: connection)
    |> result.map_error(SqliteFailure),
  )

  use exists <- result.try(table_exists(connection, "installation_setup"))
  use _ <- result.try(case exists {
    True -> Ok(Nil)
    False ->
      sqlight.exec(schema, on: connection) |> result.map_error(SqliteFailure)
  })
  seed_setup_marker(connection)
}

fn table_exists(
  connection: sqlight.Connection,
  name: String,
) -> Result(Bool, DatabaseError) {
  sqlight.query(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    on: connection,
    with: [sqlight.text(name)],
    expecting: decode.field(0, decode.int, decode.success),
  )
  |> result.map(fn(rows) { rows != [] })
  |> result.map_error(SqliteFailure)
}

fn seed_setup_marker(
  connection: sqlight.Connection,
) -> Result(Nil, DatabaseError) {
  use rows <- result.try(
    sqlight.query(
      "SELECT id FROM installation_setup WHERE id = 1",
      on: connection,
      with: [],
      expecting: decode.list(decode.int),
    )
    |> result.map_error(SqliteFailure),
  )

  case rows {
    [[1]] -> Ok(Nil)
    [] ->
      sqlight.exec(
        "INSERT INTO installation_setup (id, initialized_at, organization_id) VALUES (1, NULL, NULL)",
        on: connection,
      )
      |> result.map_error(SqliteFailure)
    _ -> Error(SchemaUnavailable)
  }
}

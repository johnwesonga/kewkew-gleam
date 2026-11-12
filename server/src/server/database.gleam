import gleam/dynamic/decode
import gleam/result
import gleam/string
import simplifile
import sqlight

pub type DatabaseError {
  SqliteFailure(String)
  SchemaUnavailable
}

/// Open the database file, create its schema if it is new, and seed the
/// singleton setup marker used to make bootstrap one-time.
pub fn open(
  path: String,
  schema_path: String,
) -> Result(sqlight.Connection, DatabaseError) {
  use connection <- result.try(
    sqlight.open(path) |> result.map_error(sqlite_error),
  )
  use schema <- result.try(
    simplifile.read(schema_path)
    |> result.map_error(fn(_) { SchemaUnavailable }),
  )
  use _ <- result.try(initialize(connection, schema))
  Ok(connection)
}

/// Initialize a connection. This is public so tests can use isolated
/// in-memory SQLite databases.
pub fn initialize(
  connection: sqlight.Connection,
  schema: String,
) -> Result(Nil, DatabaseError) {
  use _ <- result.try(
    sqlight.exec("PRAGMA foreign_keys = ON", on: connection)
    |> result.map_error(sqlite_error),
  )
  use tables <- result.try(
    sqlight.query(
      "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'installation_setup'",
      on: connection,
      with: [],
      expecting: decode.list(decode.int),
    )
    |> result.map_error(sqlite_error),
  )

  case tables {
    [[count]] if count > 0 -> seed_setup_marker(connection)
    _ -> {
      use _ <- result.try(
        sqlight.exec(schema, on: connection) |> result.map_error(sqlite_error),
      )
      seed_setup_marker(connection)
    }
  }
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
    |> result.map_error(sqlite_error),
  )

  case rows {
    [[1]] -> Ok(Nil)
    [] ->
      sqlight.exec(
        "INSERT INTO installation_setup (id, initialized_at, organization_id) VALUES (1, NULL, NULL)",
        on: connection,
      )
      |> result.map_error(sqlite_error)
    _ -> Error(SchemaUnavailable)
  }
}

fn sqlite_error(error: sqlight.Error) -> DatabaseError {
  SqliteFailure(string.inspect(error))
}

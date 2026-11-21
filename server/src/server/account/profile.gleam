import gleam/result
import gleam/string
import server/database/parrot
import server/sql
import shared
import sqlight

pub type ProfileError {
  InvalidName
  NotFound
  DatabaseFailure(String)
}

pub fn get(
  connection: sqlight.Connection,
  user_id: String,
) -> Result(shared.User, ProfileError) {
  use rows <- result.try(
    parrot.query(connection, sql.get_own_profile(user_id))
    |> result.map_error(database_failure),
  )
  case rows {
    [row] -> Ok(shared.User(row.id, row.name, row.email, row.image))
    _ -> Error(NotFound)
  }
}

pub fn update_name(
  connection: sqlight.Connection,
  user_id: String,
  name: String,
) -> Result(shared.User, ProfileError) {
  let name = string.trim(name)
  case string.length(name) >= 1 && string.length(name) <= 100 {
    False -> Error(InvalidName)
    True -> {
      use rows <- result.try(
        parrot.query(connection, sql.update_own_profile(name, user_id))
        |> result.map_error(database_failure),
      )
      case rows {
        [row] -> Ok(shared.User(row.id, row.name, row.email, row.image))
        _ -> Error(NotFound)
      }
    }
  }
}

fn database_failure(error: sqlight.Error) -> ProfileError {
  DatabaseFailure(string.inspect(error))
}

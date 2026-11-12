import envoy
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/int
import gleam/io
import mist
import server/database
import server/http
import wisp/wisp_mist

pub fn main() -> Nil {
  let database_path = case envoy.get("KEWKEW_DB_PATH") {
    Ok(path) -> path
    Error(Nil) -> "db/kewkew.sqlite3"
  }
  let port = case envoy.get("KEWKEW_PORT") {
    Ok(value) ->
      case int.parse(value) {
        Ok(port) -> port
        Error(_) -> 4000
      }
    Error(Nil) -> 4000
  }

  case secret_key_base() {
    Error(Nil) ->
      io.println("KEWKEW_SECRET_KEY_BASE is required in production.")
    Ok(secret) ->
      case database.open(database_path, "db/database.sql") {
        Error(_) -> io.println("Server failed to open or initialize SQLite.")
        Ok(connection) -> {
          let context = http.Context(database: connection)
          let handler = fn(request) { http.handle(request, context) }
          let mist_handler = wisp_mist.handler(handler, secret)
          case mist_handler |> mist.new |> mist.port(port) |> mist.start {
            Ok(_) -> process.sleep_forever()
            Error(_) -> io.println("Server failed to start.")
          }
        }
      }
  }
}

fn secret_key_base() -> Result(String, Nil) {
  case envoy.get("KEWKEW_SECRET_KEY_BASE") {
    Ok(secret) -> Ok(secret)
    Error(Nil) ->
      case envoy.get("KEWKEW_ENV") {
        Ok("production") -> Error(Nil)
        _ ->
          crypto.strong_random_bytes(64)
          |> bit_array.base64_url_encode(False)
          |> Ok
      }
  }
}

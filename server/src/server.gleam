import envoy
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/result
import mist
import server/database
import server/http
import wisp
import wisp/wisp_mist

type Config {
  Config(
    database_path: String,
    port: Int,
    secret_key_base: String,
    resend_api_key: String,
    resend_from: String,
    public_app_url: String,
  )
}

type StartError {
  MissingSecretKeyBase
  DatabaseFailed
  ServerFailed
}

pub fn main() -> Nil {
  wisp.configure_logger()
  case start() {
    Ok(_) -> process.sleep_forever()
    Error(error) -> io.println(describe(error))
  }
}

fn start() -> Result(Nil, StartError) {
  use config <- result.try(load_config())
  use connection <- result.try(
    database.open(config.database_path, "db/database.sql")
    |> result.replace_error(DatabaseFailed),
  )

  let context =
    http.Context(
      database: connection,
      resend_api_key: config.resend_api_key,
      resend_from: config.resend_from,
      public_app_url: config.public_app_url,
    )

  wisp_mist.handler(http.handle(_, context), config.secret_key_base)
  |> mist.new
  |> mist.port(config.port)
  |> mist.start
  |> result.replace(Nil)
  |> result.replace_error(ServerFailed)
}

fn load_config() -> Result(Config, StartError) {
  use secret <- result.try(
    secret_key_base() |> result.replace_error(MissingSecretKeyBase),
  )
  Ok(Config(
    database_path: env_or_default("KEWKEW_DB_PATH", "priv/kewkew.sqlite3"),
    port: env_int_or_default("KEWKEW_PORT", 4000),
    secret_key_base: secret,
    resend_api_key: env_or_empty("RESEND_API_KEY"),
    resend_from: env_or_empty("RESEND_FROM_EMAIL"),
    public_app_url: env_or_default(
      "KEWKEW_PUBLIC_APP_URL",
      "http://localhost:8080",
    ),
  ))
}

fn describe(error: StartError) -> String {
  case error {
    MissingSecretKeyBase -> "KEWKEW_SECRET_KEY_BASE is required in production."
    DatabaseFailed -> "Server failed to open or initialize SQLite."
    ServerFailed -> "Server failed to start."
  }
}

fn env_or_default(name: String, default: String) -> String {
  envoy.get(name) |> result.unwrap(default)
}

fn env_or_empty(name: String) -> String {
  env_or_default(name, "")
}

fn env_int_or_default(name: String, default: Int) -> Int {
  envoy.get(name)
  |> result.try(int.parse)
  |> result.unwrap(default)
}

fn is_production() -> Bool {
  envoy.get("KEWKEW_ENV") == Ok("production")
}

fn secret_key_base() -> Result(String, StartError) {
  case envoy.get("KEWKEW_SECRET_KEY_BASE") {
    Ok(secret) if secret != "" -> Ok(secret)
    _ ->
      case is_production() {
        True -> Error(MissingSecretKeyBase)
        False -> Ok(wisp.random_string(64))
      }
  }
}

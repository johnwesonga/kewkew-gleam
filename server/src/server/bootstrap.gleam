import envoy
import gleam/io
import gleam/result
import server/database
import server/organization/bootstrap as organization_bootstrap
import sqlight

pub fn main() -> Nil {
  case load_details() {
    Error(message) -> io.println("Bootstrap failed: " <> message)
    Ok(#(database_path, details)) -> {
      case database.open(database_path, "db/database.sql") {
        Error(_) ->
          io.println(
            "Bootstrap failed: could not open or initialize the SQLite database.",
          )
        Ok(connection) -> {
          case organization_bootstrap.create(connection, details) {
            Ok(created) -> {
              io.println("Initial organization and administrator created.")
              io.println("Organization ID: " <> created.organization_id)
              io.println("Location ID: " <> created.location_id)
              io.println("Administrator ID: " <> created.administrator_id)
            }
            Error(organization_bootstrap.AlreadyInitialized) ->
              io.println(
                "Bootstrap failed: this installation is already initialized.",
              )
            Error(organization_bootstrap.InvalidDetails(_)) ->
              io.println(
                "Bootstrap failed: check the organization, location, administrator, email, password, and timezone values.",
              )
            Error(organization_bootstrap.PasswordHashFailed) ->
              io.println(
                "Bootstrap failed: the administrator password could not be secured.",
              )
            Error(organization_bootstrap.DatabaseFailed(_)) ->
              io.println(
                "Bootstrap failed: the setup transaction could not be completed.",
              )
          }
          case sqlight.close(connection) {
            Ok(Nil) -> Nil
            Error(_) -> Nil
          }
        }
      }
    }
  }
}

fn load_details() -> Result(#(String, organization_bootstrap.Details), String) {
  let database_path = case envoy.get("KEWKEW_DB_PATH") {
    Ok(path) -> path
    Error(Nil) -> "priv/kewkew.sqlite3"
  }
  use organization_name <- result.try(required("KEWKEW_ORGANIZATION_NAME"))
  use location_name <- result.try(required("KEWKEW_LOCATION_NAME"))
  use admin_name <- result.try(required("KEWKEW_ADMIN_NAME"))
  use email <- result.try(required("KEWKEW_ADMIN_EMAIL"))
  use password <- result.try(required("KEWKEW_ADMIN_PASSWORD"))
  let timezone = case envoy.get("KEWKEW_LOCATION_TIMEZONE") {
    Ok(value) -> value
    Error(Nil) -> "UTC"
  }
  Ok(#(
    database_path,
    organization_bootstrap.Details(
      organization_name:,
      location_name:,
      admin_name:,
      email:,
      password:,
      timezone:,
    ),
  ))
}

fn required(name: String) -> Result(String, String) {
  case envoy.get(name) {
    Ok(value) -> Ok(value)
    Error(Nil) -> Error("set " <> name <> " in the trusted environment")
  }
}

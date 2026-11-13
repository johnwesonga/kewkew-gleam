import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import server/id
import server/organization/access
import sqlight

pub type ServiceError {
  InvalidName
  NotFound
  Forbidden
  DatabaseFailure(String)
}

/// Create a service at a location managed by an active organization admin.
pub fn create(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  location_id: String,
  name: String,
  description: String,
) -> Result(Nil, ServiceError) {
  use #(name, description) <- result.try(validate(name, description))
  use _ <- result.try(access.require_admin(
    connection,
    user_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  case
    sqlight.query(
      "INSERT INTO services (id, organization_id, location_id, name, description) SELECT ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM locations WHERE id = ? AND organization_id = ?) RETURNING id",
      on: connection,
      with: [
        sqlight.text(id.new()),
        sqlight.text(organization_id),
        sqlight.text(location_id),
        sqlight.text(name),
        sqlight.nullable(sqlight.text, description),
        sqlight.text(location_id),
        sqlight.text(organization_id),
      ],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Update service details while keeping the service at its existing location.
pub fn update(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
  location_id: String,
  service_id: String,
  name: String,
  description: String,
) -> Result(Nil, ServiceError) {
  use #(name, description) <- result.try(validate(name, description))
  use _ <- result.try(access.require_admin(
    connection,
    user_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  case
    sqlight.query(
      "UPDATE services SET name = ?, description = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ? AND organization_id = ? AND location_id = ? RETURNING id",
      on: connection,
      with: [
        sqlight.text(name),
        sqlight.nullable(sqlight.text, description),
        sqlight.text(service_id),
        sqlight.text(organization_id),
        sqlight.text(location_id),
      ],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn validate(
  name: String,
  description: String,
) -> Result(#(String, Option(String)), ServiceError) {
  let name = string.trim(name)
  let description = string.trim(description)
  case name {
    "" -> Error(InvalidName)
    _ ->
      Ok(
        #(name, case description {
          "" -> None
          value -> Some(value)
        }),
      )
  }
}

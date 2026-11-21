import gleam/json.{type Json}
import gleam/result
import gleam/string
import server/database/parrot
import server/sql
import sqlight

pub type QueueError {
  NotFound
  DatabaseFailure(String)
}

/// Return joinable queue choices for a public location without exposing
/// internal organization, service, or queue identifiers.
pub fn location_services(
  connection: sqlight.Connection,
  location_id: String,
) -> Result(Json, QueueError) {
  use #(organization, location) <- result.try(public_location(
    connection,
    location_id,
  ))
  use services <- result.try(
    parrot.query(connection, sql.list_public_location_services(location_id))
    |> result.map_error(database_failure),
  )
  Ok(public_location_json(organization, location, services))
}

/// Encode public location details without database access.
pub fn public_location_json(
  organization: String,
  location: String,
  services: List(sql.ListPublicLocationServices),
) -> Json {
  let details =
    json.object([
      #("organization", json.string(organization)),
      #("location", json.string(location)),
      #(
        "services",
        json.array(services, fn(service) {
          json.object([
            #("name", json.string(service.name)),
            #("queue_name", json.string(service.queue_name)),
            #("public_id", json.nullable(service.public_id, json.string)),
            #("availability_state", json.string(service.availability_state)),
            #("waiting_count", json.int(service.waiting_count)),
          ])
        }),
      ),
    ])
  details
}

fn public_location(
  connection: sqlight.Connection,
  location_id: String,
) -> Result(#(String, String), QueueError) {
  use rows <- result.try(
    parrot.query(connection, sql.get_public_location(location_id))
    |> result.map_error(database_failure),
  )
  case rows {
    [row] -> Ok(#(row.organization, row.location))
    _ -> Error(NotFound)
  }
}

fn database_failure(error: sqlight.Error) -> QueueError {
  DatabaseFailure(string.inspect(error))
}

/// Find the visitor-safe details for a queue through its unguessable public ID.
pub fn public_queue(
  connection: sqlight.Connection,
  public_id: String,
) -> Result(Json, QueueError) {
  use rows <- result.try(
    parrot.query(connection, sql.get_public_queue(public_id))
    |> result.map_error(database_failure),
  )
  case rows {
    [row] -> Ok(public_queue_json(row))
    _ -> Error(NotFound)
  }
}

/// Encode public queue details without database access.
pub fn public_queue_json(row: sql.GetPublicQueue) -> Json {
  json.object([
    #("organization", json.string(row.organization)),
    #("location_id", json.string(row.location_id)),
    #("location", json.string(row.location)),
    #("service", json.string(row.service)),
    #("queue", json.string(row.queue)),
    #("identity_policy", json.string(row.identity_policy)),
    #("availability_state", json.string(row.availability_state)),
    #("available", json.bool(row.available != 0)),
    #(
      "scheduled_service_start_at",
      json.nullable(row.scheduled_service_start_at, json.string),
    ),
  ])
}

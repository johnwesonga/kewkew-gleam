import gleam/dynamic/decode
import gleam/json
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
) -> Result(String, QueueError) {
  case
    sqlight.query(
      "SELECT json_object('organization', organizations.name, 'location', locations.name, 'services', json(COALESCE((SELECT json_group_array(json_object('name', services.name, 'queue_name', queues.name, 'public_id', queues.public_id, 'availability_state', CASE WHEN queues.is_active = 0 OR services.is_active = 0 OR locations.is_active = 0 THEN 'closed' WHEN sessions.id IS NULL OR sessions.state = 'closed' OR sessions.occurrence_status <> 'active' THEN 'closed' WHEN sessions.state = 'paused' THEN 'paused' WHEN sessions.signup_opens_at IS NOT NULL AND sessions.signup_opens_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now') THEN 'closed' WHEN (queues.active_ticket_capacity IS NOT NULL AND (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) >= queues.active_ticket_capacity) OR (sessions.occurrence_ticket_cap IS NOT NULL AND (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) >= sessions.occurrence_ticket_cap) THEN 'full' ELSE 'open' END, 'waiting_count', (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status = 'waiting'))) FROM services JOIN queues ON queues.service_id = services.id AND queues.location_id = services.location_id LEFT JOIN queue_sessions sessions ON sessions.id = (SELECT latest.id FROM queue_sessions latest WHERE latest.queue_id = queues.id ORDER BY latest.opened_at DESC, latest.id DESC LIMIT 1) WHERE services.location_id = locations.id AND queues.public_id IS NOT NULL), json('[]')))) FROM locations JOIN organizations ON organizations.id = locations.organization_id WHERE locations.id = ? AND locations.is_active = 1 LIMIT 1",
      on: connection,
      with: [sqlight.text(location_id)],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[details]]) -> Ok(details)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Find the visitor-safe details for a queue through its unguessable public ID.
pub fn lookup(
  connection: sqlight.Connection,
  public_id: String,
) -> Result(String, QueueError) {
  case parrot.query(connection, sql.get_public_queue(public_id)) {
    Ok([
      sql.GetPublicQueue(
        organization,
        location_id,
        location,
        service,
        queue,
        identity_policy,
        availability_state,
        available,
        scheduled_service_start_at,
      ),
    ]) ->
      json.object([
        #("organization", json.string(organization)),
        #("location_id", json.string(location_id)),
        #("location", json.string(location)),
        #("service", json.string(service)),
        #("queue", json.string(queue)),
        #("identity_policy", json.string(identity_policy)),
        #("availability_state", json.string(availability_state)),
        #("available", json.bool(available == 1)),
        #(
          "scheduled_service_start_at",
          json.nullable(scheduled_service_start_at, json.string),
        ),
      ])
      |> json.to_string
      |> Ok
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

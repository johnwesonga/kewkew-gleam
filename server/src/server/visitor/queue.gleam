import gleam/dynamic/decode
import gleam/string
import sqlight

pub type QueueError {
  NotFound
  DatabaseFailure(String)
}

/// Find the visitor-safe details for a queue through its unguessable public ID.
pub fn lookup(
  connection: sqlight.Connection,
  public_id: String,
) -> Result(String, QueueError) {
  case
    sqlight.query(
      "SELECT json_object('organization', organizations.name, 'location', locations.name, 'service', services.name, 'queue', queues.name, 'availability_state', CASE WHEN queues.is_active = 0 OR locations.is_active = 0 OR services.is_active = 0 THEN 'closed' WHEN sessions.id IS NULL OR sessions.state = 'closed' THEN 'closed' WHEN sessions.state = 'paused' THEN 'paused' WHEN sessions.occurrence_status = 'blocked' THEN 'closed' WHEN (queues.active_ticket_capacity IS NOT NULL AND (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) >= queues.active_ticket_capacity) OR (sessions.occurrence_ticket_cap IS NOT NULL AND (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) >= sessions.occurrence_ticket_cap) THEN 'full' ELSE 'open' END, 'available', json(CASE WHEN queues.is_active = 1 AND locations.is_active = 1 AND services.is_active = 1 AND sessions.state = 'open' AND sessions.occurrence_status = 'active' AND (queues.active_ticket_capacity IS NULL OR (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) < queues.active_ticket_capacity) AND (sessions.occurrence_ticket_cap IS NULL OR (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) < sessions.occurrence_ticket_cap) THEN 'true' ELSE 'false' END), 'scheduled_service_start_at', sessions.scheduled_service_start_at) FROM queues JOIN organizations ON organizations.id = queues.organization_id JOIN locations ON locations.id = queues.location_id JOIN services ON services.id = queues.service_id LEFT JOIN queue_sessions sessions ON sessions.id = (SELECT latest.id FROM queue_sessions latest WHERE latest.queue_id = queues.id ORDER BY latest.opened_at DESC, latest.id DESC LIMIT 1) WHERE queues.public_id = ? LIMIT 1",
      on: connection,
      with: [sqlight.text(public_id)],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[details]]) -> Ok(details)
    Ok(_) -> Error(NotFound)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

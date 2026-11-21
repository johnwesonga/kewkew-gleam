-- name: GetPublicQueue :one
SELECT
  organizations.name AS organization,
  locations.id AS location_id,
  locations.name AS location,
  services.name AS service,
  queues.name AS queue,
  queues.identity_policy,
  CAST(CASE
    WHEN queues.is_active = 0 OR locations.is_active = 0 OR services.is_active = 0 THEN 'closed'
    WHEN sessions.id IS NULL OR sessions.state = 'closed' THEN 'closed'
    WHEN sessions.state = 'paused' THEN 'paused'
    WHEN sessions.signup_opens_at IS NOT NULL AND sessions.signup_opens_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now') THEN 'closed'
    WHEN sessions.occurrence_status = 'blocked' THEN 'closed'
    WHEN (queues.active_ticket_capacity IS NOT NULL AND (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) >= queues.active_ticket_capacity)
      OR (sessions.occurrence_ticket_cap IS NOT NULL AND (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) >= sessions.occurrence_ticket_cap) THEN 'full'
    ELSE 'open'
  END AS TEXT) AS availability_state,
  CASE
    WHEN queues.is_active = 1 AND locations.is_active = 1 AND services.is_active = 1
      AND sessions.state = 'open' AND sessions.occurrence_status = 'active'
      AND (sessions.signup_opens_at IS NULL OR sessions.signup_opens_at <= strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
      AND (queues.active_ticket_capacity IS NULL OR (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) < queues.active_ticket_capacity)
      AND (sessions.occurrence_ticket_cap IS NULL OR (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving')) < sessions.occurrence_ticket_cap)
    THEN 1 ELSE 0
  END AS available,
  sessions.scheduled_service_start_at
FROM queues
JOIN organizations ON organizations.id = queues.organization_id
JOIN locations ON locations.id = queues.location_id
JOIN services ON services.id = queues.service_id
LEFT JOIN queue_sessions sessions ON sessions.id = (
  SELECT latest.id FROM queue_sessions latest
  WHERE latest.queue_id = queues.id
  ORDER BY latest.opened_at DESC, latest.id DESC
  LIMIT 1
)
WHERE queues.public_id = CAST(sqlc.arg(public_id) AS TEXT)
LIMIT 1;

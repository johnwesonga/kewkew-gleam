-- name: TicketAttemptTokenUsed :one
SELECT count(*) AS count FROM tracking_credentials WHERE token_digest = CAST(sqlc.arg(digest) AS TEXT);
-- name: TrackVisitorTicket :one
SELECT CAST(json_object('organization', organizations.name, 'ticket_number', tickets.ticket_number, 'status', tickets.status, 'queue_position', CASE WHEN tickets.status = 'waiting' THEN 1 + (SELECT count(*)
FROM tickets ahead
WHERE ahead.queue_session_id = tickets.queue_session_id
AND ahead.status = 'waiting'
AND ahead.queue_sequence < tickets.queue_sequence) ELSE NULL END, 'queue', queues.name, 'service', services.name, 'location', locations.name, 'scheduled_service_start_at', queue_sessions.scheduled_service_start_at, 'visitor_first_name', tickets.first_name, 'visitor_instructions', services.description) AS TEXT) AS payload
FROM tracking_credentials
JOIN tickets ON tickets.id = tracking_credentials.ticket_id
JOIN queues ON queues.id = tickets.queue_id
JOIN services ON services.id = queues.service_id
JOIN organizations ON organizations.id = tickets.organization_id
JOIN locations ON locations.id = queues.location_id
JOIN queue_sessions ON queue_sessions.id = tickets.queue_session_id
WHERE tracking_credentials.token_digest = CAST(sqlc.arg(digest) AS TEXT)
AND tracking_credentials.revoked_at IS NULL
AND (tracking_credentials.expires_at IS NULL OR tracking_credentials.expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
LIMIT 1;
-- name: GetVisitorCancellationTicket :one
SELECT tickets.id, tickets.status
FROM tracking_credentials
JOIN tickets ON tickets.id = tracking_credentials.ticket_id
WHERE tracking_credentials.token_digest = CAST(sqlc.arg(digest) AS TEXT)
AND tracking_credentials.revoked_at IS NULL
AND (tracking_credentials.expires_at IS NULL OR tracking_credentials.expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
LIMIT 1;
-- name: CancelVisitorTicket :one
UPDATE tickets SET status = 'cancelled', cancelled_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = sqlc.arg(ticket_id)
AND status = 'waiting'
RETURNING id;
-- name: RecordVisitorCancellation :one
INSERT INTO ticket_events (id, ticket_id, from_status, to_status, actor_type, occurred_at, created_at)
VALUES (sqlc.arg(event_id), sqlc.arg(ticket_id), 'waiting', 'cancelled', 'visitor', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
RETURNING id;
-- name: ReserveVisitorTicketNumbers :one
UPDATE queue_sessions
SET next_ticket_number = next_ticket_number + 1,
next_queue_sequence = next_queue_sequence + 1
WHERE id = sqlc.arg(session_id) AND state = 'open' AND occurrence_status = 'active'
RETURNING next_ticket_number, next_queue_sequence;
-- name: CreateVisitorTicket :one
INSERT INTO tickets (id, organization_id, queue_id, queue_session_id, ticket_number, queue_sequence, join_attempt_digest, status, identity_policy, first_name, last_name, joined_at, created_at, updated_at)
VALUES (sqlc.arg(ticket_id), (SELECT organization_id
FROM queues
WHERE id = sqlc.arg(queue_id)), sqlc.arg(queue_id), sqlc.arg(session_id), sqlc.arg(ticket_number), sqlc.arg(queue_sequence), CAST(sqlc.arg(digest) AS TEXT), 'waiting', sqlc.arg(identity_policy), sqlc.narg(first_name), sqlc.narg(last_name), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
RETURNING id;
-- name: RecordVisitorJoin :one
INSERT INTO ticket_events (id, ticket_id, from_status, to_status, actor_type, occurred_at, created_at)
VALUES (sqlc.arg(event_id), sqlc.arg(ticket_id), NULL, 'waiting', 'visitor', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
RETURNING id;
-- name: CreateVisitorTrackingCredential :one
INSERT INTO tracking_credentials (id, ticket_id, token_digest, created_at, expires_at)
VALUES (sqlc.arg(credential_id), sqlc.arg(ticket_id), CAST(sqlc.arg(digest) AS TEXT), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+1 day'))
RETURNING id;
-- name: ReplayVisitorJoin :one
SELECT CAST(json_object('ticket_number', tickets.ticket_number, 'status', tickets.status, 'queue', queues.name, 'service', services.name, 'location', locations.name, 'tracking_token', CAST(sqlc.arg(token) AS TEXT)) AS TEXT) AS payload
FROM tickets
JOIN queues ON queues.id = tickets.queue_id
JOIN services ON services.id = queues.service_id
JOIN locations ON locations.id = queues.location_id
WHERE queues.public_id = CAST(sqlc.arg(public_id) AS TEXT)
AND tickets.join_attempt_digest = CAST(sqlc.arg(digest) AS TEXT)
LIMIT 1;
-- name: GetVisitorJoinTarget :one
SELECT queues.id AS queue_id, queues.identity_policy, sessions.id AS session_id,
queues.active_ticket_capacity AS queue_capacity,
sessions.occurrence_ticket_cap AS occurrence_capacity,
(SELECT count(*)
FROM tickets
WHERE queue_session_id = sessions.id
AND status IN ('waiting', 'called', 'serving')) AS active_count
FROM queues
JOIN locations ON locations.id = queues.location_id
JOIN services ON services.id = queues.service_id
JOIN queue_sessions sessions ON sessions.id = (SELECT latest.id
FROM queue_sessions latest
WHERE latest.queue_id = queues.id ORDER BY latest.opened_at DESC, latest.id DESC
LIMIT 1)
WHERE queues.public_id = CAST(sqlc.arg(public_id) AS TEXT)
AND queues.is_active = 1
AND locations.is_active = 1
AND services.is_active = 1
AND sessions.state = 'open'
AND sessions.occurrence_status = 'active'
AND (sessions.signup_opens_at IS NULL OR sessions.signup_opens_at <= strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
LIMIT 1;

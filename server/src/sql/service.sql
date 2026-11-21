-- name: CreateService :one
INSERT INTO services (id, organization_id, location_id, name, description)
SELECT sqlc.arg(id), sqlc.arg(organization_id), sqlc.arg(location_id), sqlc.arg(name), sqlc.narg(description)
WHERE EXISTS (
  SELECT 1
  FROM locations
  WHERE locations.id = sqlc.arg(authorized_location_id)
    AND locations.organization_id = sqlc.arg(authorized_organization_id)
)
RETURNING id;

-- name: ListOverviewServices :many
SELECT id, organization_id, location_id, name, description,
       is_active, created_at, updated_at
FROM services
WHERE organization_id = sqlc.arg(organization_id)
  AND location_id = sqlc.arg(location_id)
ORDER BY name;

-- name: ListOverviewQueues :many
SELECT queues.id, queues.organization_id, queues.location_id, queues.service_id,
       queues.name, queues.identity_policy, queues.active_ticket_capacity,
       queues.is_active,
       latest_session.state AS current_session_state,
       queues.public_id, queues.created_at, queues.updated_at
FROM queues
LEFT JOIN queue_sessions AS latest_session
  ON latest_session.id = (
    SELECT queue_sessions.id
    FROM queue_sessions
    WHERE queue_sessions.organization_id = queues.organization_id
      AND queue_sessions.queue_id = queues.id
    ORDER BY queue_sessions.opened_at DESC, queue_sessions.id DESC
    LIMIT 1
  )
WHERE queues.organization_id = sqlc.arg(organization_id)
  AND queues.location_id = sqlc.arg(location_id)
  AND queues.service_id = sqlc.arg(service_id)
ORDER BY queues.name;

-- name: SetServiceActive :one
UPDATE services
SET is_active = sqlc.arg(is_active), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = sqlc.arg(id)
  AND organization_id = sqlc.arg(organization_id)
  AND location_id = sqlc.arg(location_id)
RETURNING id;

-- name: UpdateService :one
UPDATE services
SET name = sqlc.arg(name), description = sqlc.narg(description), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = sqlc.arg(id)
  AND organization_id = sqlc.arg(organization_id)
  AND location_id = sqlc.arg(location_id)
RETURNING id;

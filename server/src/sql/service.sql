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

-- name: UpdateService :one
UPDATE services
SET name = sqlc.arg(name), description = sqlc.narg(description), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = sqlc.arg(id)
  AND organization_id = sqlc.arg(organization_id)
  AND location_id = sqlc.arg(location_id)
RETURNING id;

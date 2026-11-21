-- name: CreateLocation :one
INSERT INTO locations (id, organization_id, name, timezone)
SELECT sqlc.arg(id), sqlc.arg(organization_id), sqlc.arg(name), sqlc.arg(timezone)
WHERE EXISTS (
  SELECT 1
  FROM organization_memberships
  WHERE organization_memberships.organization_id = sqlc.arg(authorized_organization_id)
    AND organization_memberships.user_id = sqlc.arg(user_id)
    AND organization_memberships.role = 'admin'
    AND organization_memberships.status = 'active'
)
RETURNING id;

-- name: ListOverviewLocations :many
SELECT locations.id, locations.organization_id, locations.name, locations.timezone,
       locations.is_active, locations.created_at, locations.updated_at
FROM locations
WHERE locations.organization_id = sqlc.arg(organization_id)
  AND (CAST(sqlc.arg(role) AS TEXT) = 'admin' OR EXISTS (
    SELECT 1
    FROM membership_location_access mla
    WHERE mla.organization_id = locations.organization_id
      AND mla.user_id = sqlc.arg(user_id)
      AND mla.location_id = locations.id
  ))
ORDER BY locations.name;

-- name: SetLocationActive :one
UPDATE locations
SET is_active = sqlc.arg(is_active), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = sqlc.arg(id)
  AND organization_id = sqlc.arg(organization_id)
RETURNING id;

-- name: UpdateLocation :one
UPDATE locations
SET name = sqlc.arg(name), timezone = sqlc.arg(timezone), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE locations.id = sqlc.arg(id)
  AND locations.organization_id = sqlc.arg(organization_id)
  AND EXISTS (
    SELECT 1
    FROM organization_memberships
    WHERE organization_memberships.organization_id = sqlc.arg(authorized_organization_id)
      AND organization_memberships.user_id = sqlc.arg(user_id)
      AND organization_memberships.role = 'admin'
      AND organization_memberships.status = 'active'
  )
RETURNING id;

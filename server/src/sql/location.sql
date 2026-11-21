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

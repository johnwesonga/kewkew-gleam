-- name: UpdateOrganizationName :one
UPDATE organizations
SET name = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = ?
RETURNING id;

-- name: GetOrganization :one
SELECT id, name, created_at, updated_at
FROM organizations
WHERE id = sqlc.arg(id);


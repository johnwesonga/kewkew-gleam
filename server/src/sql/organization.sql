-- name: UpdateOrganizationName :one
UPDATE organizations
SET name = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = ?
RETURNING id;


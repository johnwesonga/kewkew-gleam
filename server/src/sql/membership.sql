-- name: GetActiveMembershipRole :one
SELECT role
FROM organization_memberships
WHERE organization_id = sqlc.arg(organization_id)
  AND user_id = sqlc.arg(user_id)
  AND status = 'active'
LIMIT 1;

-- name: ListActiveOrganizationIDs :many
SELECT organization_id
FROM organization_memberships
WHERE user_id = sqlc.arg(user_id)
  AND status = 'active'
ORDER BY organization_id;

-- name: GetActiveMembership :one
SELECT user_id
FROM organization_memberships
WHERE organization_id = sqlc.arg(organization_id)
  AND user_id = sqlc.arg(user_id)
  AND status = 'active'
LIMIT 1;

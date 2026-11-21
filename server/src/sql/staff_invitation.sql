-- name: RetireUnusableInvitations :many
UPDATE staff_invitations
SET revoked_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE organization_id = sqlc.arg(organization_id)
  AND invited_email = sqlc.arg(email)
  AND accepted_at IS NULL AND revoked_at IS NULL
  AND (delivery_state = 'failed' OR expires_at <= strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
RETURNING id;

-- name: CountOpenInvitations :one
SELECT count(*) AS count FROM staff_invitations
WHERE organization_id = sqlc.arg(organization_id)
  AND invited_email = sqlc.arg(email)
  AND accepted_at IS NULL AND revoked_at IS NULL;

-- name: ClearInviteeLocationAccess :many
DELETE FROM membership_location_access
WHERE organization_id = sqlc.arg(organization_id) AND user_id = sqlc.arg(user_id)
RETURNING location_id;

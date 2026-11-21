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

-- name: ListSentStaffInvitations :many
SELECT CAST(
json_object('id', id,
'organization_id', organization_id,
'invited_email', invited_email,
'role', role,
'location_ids', json(location_ids_json),
'created_by_user_id', created_by_user_id,
'created_at', created_at,
'expires_at', expires_at,
'delivery_state', delivery_state,
'accepted_by_user_id', accepted_by_user_id,
'accepted_at', accepted_at,
'revoked_at', revoked_at) AS TEXT) AS payload
FROM
staff_invitations WHERE organization_id = CAST(sqlc.arg(organization_id) AS TEXT)
AND delivery_state = 'sent'
ORDER BY created_at DESC;

-- name: CreateStaffInvitation :one
INSERT INTO staff_invitations
(id, organization_id, invited_email, role, location_ids_json, token_digest, created_by_user_id, created_at, expires_at, delivery_state)
VALUES (CAST(sqlc.arg(id) AS TEXT), CAST(sqlc.arg(organization_id) AS TEXT), CAST(sqlc.arg(email) AS TEXT), CAST(sqlc.arg(role) AS TEXT), CAST(sqlc.arg(location_ids_json) AS TEXT), CAST(sqlc.arg(digest) AS TEXT), CAST(sqlc.arg(inviter_id) AS TEXT), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+7 days'), 'pending')
RETURNING expires_at;

-- name: SetInvitationDeliveryState :one
UPDATE staff_invitations SET delivery_state = CAST(sqlc.arg(state) AS TEXT)
WHERE id = CAST(sqlc.arg(id) AS TEXT)
AND delivery_state IN ('pending', 'failed')
AND revoked_at IS NULL
AND accepted_at IS NULL
RETURNING id;

-- name: GetAcceptableStaffInvitation :one
SELECT id, organization_id, invited_email, role, location_ids_json
FROM staff_invitations
WHERE token_digest = CAST(sqlc.arg(digest) AS TEXT)
AND delivery_state = 'sent'
AND accepted_at IS NULL
AND revoked_at IS NULL
AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now');

-- name: GetInvitationIdentityByEmail :one
SELECT id FROM users WHERE email = CAST(sqlc.arg(email) AS TEXT) COLLATE NOCASE LIMIT 1;

-- name: CreateInvitedUser :one
INSERT INTO users (id, name, email, email_verified)
VALUES (CAST(sqlc.arg(user_id) AS TEXT), CAST(sqlc.arg(name) AS TEXT), CAST(sqlc.arg(email) AS TEXT), 0)
RETURNING id;

-- name: CreateInvitedCredential :one
INSERT INTO accounts (id, account_id, provider_id, user_id, password, created_at, updated_at)
VALUES (CAST(sqlc.arg(account_id) AS TEXT), CAST(sqlc.arg(user_id) AS TEXT), 'credential', CAST(sqlc.arg(user_id) AS TEXT), CAST(sqlc.arg(password_hash) AS TEXT), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
RETURNING id;

-- name: ActivateInvitedMembership :one
INSERT INTO organization_memberships (organization_id, user_id, role, status)
VALUES (CAST(sqlc.arg(organization_id) AS TEXT), CAST(sqlc.arg(user_id) AS TEXT), CAST(sqlc.arg(role) AS TEXT), 'active')
ON CONFLICT (organization_id, user_id)
DO UPDATE SET role = excluded.role, status = 'active', updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
RETURNING user_id;

-- name: MarkStaffInvitationAccepted :one
UPDATE staff_invitations SET accepted_by_user_id = CAST(sqlc.arg(user_id) AS TEXT), accepted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = CAST(sqlc.arg(invitation_id) AS TEXT)
AND accepted_at IS NULL
RETURNING id;

-- name: RecordInvitationAcceptance :one
INSERT INTO membership_audit_events (id, organization_id, actor_user_id, subject_user_id, change_type, after_role, after_status, details_json)
SELECT CAST(sqlc.arg(id) AS TEXT), CAST(sqlc.arg(organization_id) AS TEXT), created_by_user_id, CAST(sqlc.arg(user_id) AS TEXT), 'invitation_accepted', CAST(sqlc.arg(role) AS TEXT), 'active', json_object('invitation_id', CAST(sqlc.arg(invitation_id) AS TEXT))
FROM staff_invitations
WHERE id = CAST(sqlc.arg(invitation_id) AS TEXT)
RETURNING id;

-- name: GetInvitationIdentityEmail :one
SELECT email FROM users WHERE id = CAST(sqlc.arg(user_id) AS TEXT) LIMIT 1;

-- name: AssignInvitedLocation :one
INSERT INTO membership_location_access (organization_id, user_id, location_id)
VALUES (CAST(sqlc.arg(organization_id) AS TEXT), CAST(sqlc.arg(user_id) AS TEXT), CAST(sqlc.arg(location_id) AS TEXT))
RETURNING location_id;

-- name: CountInvitationLocation :one
SELECT count(*) AS count FROM locations
WHERE organization_id = sqlc.arg(organization_id) AND id = sqlc.arg(location_id);

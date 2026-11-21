-- name: ListStaffMembers :many
SELECT m.organization_id, m.user_id, users.name, users.email, m.role, m.status
FROM organization_memberships m JOIN users ON users.id = m.user_id
WHERE m.organization_id = sqlc.arg(organization_id)
ORDER BY users.name, users.id;

-- name: GetStaffMember :one
SELECT role, status FROM organization_memberships
WHERE organization_id = sqlc.arg(organization_id) AND user_id = sqlc.arg(user_id);

-- name: CountActiveAdministrators :one
SELECT count(*) AS count FROM organization_memberships
WHERE organization_id = sqlc.arg(organization_id) AND role = 'admin' AND status = 'active';

-- name: SetStaffMemberStatus :one
UPDATE organization_memberships SET status = sqlc.arg(status), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE organization_id = sqlc.arg(organization_id) AND user_id = sqlc.arg(user_id)
RETURNING user_id;

-- name: RecordStaffStatusChange :one
INSERT INTO membership_audit_events (id, organization_id, actor_user_id, subject_user_id, change_type, before_role, after_role, before_status, after_status)
VALUES (sqlc.arg(id), sqlc.arg(organization_id), sqlc.arg(actor_user_id), sqlc.arg(subject_user_id), sqlc.arg(change_type), sqlc.arg(role), sqlc.arg(role), sqlc.arg(before_status), sqlc.arg(after_status))
RETURNING id;

-- Preserve invitations while allowing the pending provider-delivery state.
BEGIN IMMEDIATE;
CREATE TABLE staff_invitations_v2 (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	invited_email TEXT NOT NULL COLLATE NOCASE,
	role TEXT NOT NULL CHECK (role IN ('admin', 'operator')),
	location_ids_json TEXT NOT NULL CHECK (json_valid(location_ids_json)),
	token_digest TEXT NOT NULL UNIQUE,
	created_by_user_id TEXT NOT NULL,
	created_at TEXT NOT NULL,
	expires_at TEXT NOT NULL,
	delivery_state TEXT NOT NULL CHECK (delivery_state IN ('pending', 'sent', 'failed')),
	accepted_by_user_id TEXT,
	accepted_at TEXT,
	revoked_at TEXT,
	FOREIGN KEY (organization_id) REFERENCES organizations (id) ON DELETE RESTRICT,
	FOREIGN KEY (organization_id, created_by_user_id)
		REFERENCES organization_memberships (organization_id, user_id) ON DELETE RESTRICT,
	FOREIGN KEY (accepted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
INSERT INTO staff_invitations_v2 (id, organization_id, invited_email, role, location_ids_json, token_digest, created_by_user_id, created_at, expires_at, delivery_state, accepted_by_user_id, accepted_at, revoked_at)
SELECT id, organization_id, invited_email, role, location_ids_json, token_digest, created_by_user_id, created_at, expires_at, delivery_state, accepted_by_user_id, accepted_at, revoked_at FROM staff_invitations;
DROP TABLE staff_invitations;
ALTER TABLE staff_invitations_v2 RENAME TO staff_invitations;
CREATE INDEX staff_invitations_by_org_email
	ON staff_invitations (organization_id, invited_email, created_at DESC);
CREATE UNIQUE INDEX one_open_staff_invitation_per_email
	ON staff_invitations (organization_id, invited_email)
	WHERE accepted_at IS NULL AND revoked_at IS NULL;

CREATE TRIGGER staff_invitations_no_token_digest_update
BEFORE UPDATE OF token_digest ON staff_invitations
BEGIN
	SELECT RAISE(ABORT, 'invitation token digest is immutable');
END;
PRAGMA user_version = 2;
COMMIT;

PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE IF NOT EXISTS "d1_migrations"(
		id         INTEGER PRIMARY KEY AUTOINCREMENT,
		name       TEXT UNIQUE,
		applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE TABLE app_meta (
	key TEXT PRIMARY KEY,
	value TEXT NOT NULL
);
CREATE TABLE organizations (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL CHECK (length(trim(name)) > 0),
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE TABLE users (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL CHECK (length(trim(name)) > 0),
	email TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK (length(trim(email)) > 3),
	email_verified INTEGER NOT NULL DEFAULT 0 CHECK (email_verified IN (0, 1)),
	image TEXT,
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE TABLE organization_memberships (
	organization_id TEXT NOT NULL,
	user_id TEXT NOT NULL,
	role TEXT NOT NULL CHECK (role IN ('admin', 'operator')),
	status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	PRIMARY KEY (organization_id, user_id),
	FOREIGN KEY (organization_id) REFERENCES organizations (id) ON DELETE RESTRICT,
	FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE locations (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	name TEXT NOT NULL CHECK (length(trim(name)) > 0),
	timezone TEXT NOT NULL CHECK (length(trim(timezone)) > 0),
	is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	UNIQUE (organization_id, id),
	FOREIGN KEY (organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);
CREATE TABLE services (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	location_id TEXT NOT NULL,
	name TEXT NOT NULL CHECK (length(trim(name)) > 0),
	description TEXT,
	is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	UNIQUE (organization_id, id),
	FOREIGN KEY (organization_id, location_id)
		REFERENCES locations (organization_id, id) ON DELETE RESTRICT
);
CREATE TABLE membership_location_access (
	organization_id TEXT NOT NULL,
	user_id TEXT NOT NULL,
	location_id TEXT NOT NULL,
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	PRIMARY KEY (organization_id, user_id, location_id),
	FOREIGN KEY (organization_id, user_id)
		REFERENCES organization_memberships (organization_id, user_id) ON DELETE RESTRICT,
	FOREIGN KEY (organization_id, location_id)
		REFERENCES locations (organization_id, id) ON DELETE RESTRICT
);
CREATE TABLE membership_audit_events (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	actor_user_id TEXT NOT NULL,
	subject_user_id TEXT NOT NULL,
	change_type TEXT NOT NULL CHECK (
		change_type IN (
			'membership_created',
			'role_changed',
			'location_access_changed',
			'suspended',
			'reactivated',
			'invitation_accepted'
		)
	),
	before_role TEXT CHECK (before_role IS NULL OR before_role IN ('admin', 'operator')),
	after_role TEXT CHECK (after_role IS NULL OR after_role IN ('admin', 'operator')),
	before_status TEXT CHECK (before_status IS NULL OR before_status IN ('active', 'suspended')),
	after_status TEXT CHECK (after_status IS NULL OR after_status IN ('active', 'suspended')),
	details_json TEXT CHECK (details_json IS NULL OR json_valid(details_json)),
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	FOREIGN KEY (organization_id, actor_user_id)
		REFERENCES organization_memberships (organization_id, user_id) ON DELETE RESTRICT,
	FOREIGN KEY (organization_id, subject_user_id)
		REFERENCES organization_memberships (organization_id, user_id) ON DELETE RESTRICT
);
CREATE TABLE sessions (
	id TEXT PRIMARY KEY,
	expires_at TEXT NOT NULL,
	token TEXT NOT NULL UNIQUE,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL,
	ip_address TEXT,
	user_agent TEXT,
	user_id TEXT NOT NULL,
	FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE accounts (
	id TEXT PRIMARY KEY,
	account_id TEXT NOT NULL,
	provider_id TEXT NOT NULL,
	user_id TEXT NOT NULL,
	access_token TEXT,
	refresh_token TEXT,
	id_token TEXT,
	access_token_expires_at TEXT,
	refresh_token_expires_at TEXT,
	scope TEXT,
	password TEXT,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL,
	FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE verifications (
	id TEXT PRIMARY KEY,
	identifier TEXT NOT NULL,
	value TEXT NOT NULL,
	expires_at TEXT NOT NULL,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);
CREATE TABLE installation_setup (
	id INTEGER PRIMARY KEY CHECK (id = 1),
	initialized_at TEXT,
	organization_id TEXT,
	CHECK (
		(initialized_at IS NULL AND organization_id IS NULL)
		OR (initialized_at IS NOT NULL AND organization_id IS NOT NULL)
	),
	FOREIGN KEY (organization_id) REFERENCES organizations (id) ON DELETE RESTRICT
);
CREATE TABLE IF NOT EXISTS "rate_limits" (
	id TEXT PRIMARY KEY,
	key TEXT NOT NULL UNIQUE,
	count INTEGER NOT NULL,
	last_request INTEGER NOT NULL
);
CREATE TABLE staff_invitations (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	invited_email TEXT NOT NULL COLLATE NOCASE,
	role TEXT NOT NULL CHECK (role IN ('admin', 'operator')),
	location_ids_json TEXT NOT NULL CHECK (json_valid(location_ids_json)),
	token_digest TEXT NOT NULL UNIQUE,
	created_by_user_id TEXT NOT NULL,
	created_at TEXT NOT NULL,
	expires_at TEXT NOT NULL,
	delivery_state TEXT NOT NULL CHECK (delivery_state IN ('sent', 'failed')),
	accepted_by_user_id TEXT,
	accepted_at TEXT,
	revoked_at TEXT,
	FOREIGN KEY (organization_id) REFERENCES organizations (id) ON DELETE RESTRICT,
	FOREIGN KEY (organization_id, created_by_user_id)
		REFERENCES organization_memberships (organization_id, user_id) ON DELETE RESTRICT,
	FOREIGN KEY (accepted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE queues (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	location_id TEXT NOT NULL,
	service_id TEXT NOT NULL,
	name TEXT NOT NULL CHECK (length(trim(name)) > 0),
	identity_policy TEXT NOT NULL CHECK (identity_policy IN ('anonymous', 'name_required')),
	active_ticket_capacity INTEGER CHECK (active_ticket_capacity IS NULL OR active_ticket_capacity > 0),
	is_active INTEGER NOT NULL DEFAULT 0 CHECK (is_active IN (0, 1)),
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), created_by_user_id TEXT REFERENCES users (id) ON DELETE RESTRICT, create_request_id TEXT, public_id TEXT,
	UNIQUE (organization_id, id),
	FOREIGN KEY (organization_id, location_id)
		REFERENCES locations (organization_id, id) ON DELETE RESTRICT,
	FOREIGN KEY (organization_id, service_id)
		REFERENCES services (organization_id, id) ON DELETE RESTRICT
);
CREATE TABLE queue_sessions (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	queue_id TEXT NOT NULL,
	state TEXT NOT NULL CHECK (state IN ('open', 'paused', 'closed')),
	opened_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	closed_at TEXT, open_request_id TEXT, transition_request_id TEXT, next_ticket_number INTEGER NOT NULL DEFAULT 1 CHECK (next_ticket_number > 0), next_queue_sequence INTEGER NOT NULL DEFAULT 1 CHECK (next_queue_sequence > 0), last_join_attempt_digest TEXT, schedule_id TEXT REFERENCES queue_schedules(id), schedule_version INTEGER, occurrence_key TEXT, signup_opens_at TEXT, scheduled_service_start_at TEXT, occurrence_ticket_cap INTEGER CHECK (occurrence_ticket_cap IS NULL OR occurrence_ticket_cap > 0), occurrence_status TEXT NOT NULL DEFAULT 'active' CHECK (occurrence_status IN ('active', 'blocked')),
	FOREIGN KEY (organization_id, queue_id)
		REFERENCES queues (organization_id, id) ON DELETE RESTRICT,
	CHECK ((state = 'closed' AND closed_at IS NOT NULL) OR (state <> 'closed' AND closed_at IS NULL))
);
CREATE TABLE queue_session_events (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	queue_id TEXT NOT NULL,
	session_id TEXT NOT NULL REFERENCES queue_sessions (id) ON DELETE RESTRICT,
	from_state TEXT NOT NULL CHECK (from_state IN ('open', 'paused')),
	to_state TEXT NOT NULL CHECK (to_state IN ('open', 'paused', 'closed')),
	actor_user_id TEXT NOT NULL,
	request_id TEXT NOT NULL UNIQUE,
	occurred_at TEXT NOT NULL,
	CHECK (from_state <> to_state)
);
CREATE TABLE tickets (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	queue_id TEXT NOT NULL,
	queue_session_id TEXT NOT NULL REFERENCES queue_sessions (id) ON DELETE RESTRICT,
	ticket_number INTEGER NOT NULL CHECK (ticket_number > 0),
	queue_sequence INTEGER NOT NULL CHECK (queue_sequence > 0),
	join_attempt_digest TEXT NOT NULL,
	status TEXT NOT NULL CHECK (status IN ('waiting', 'called', 'serving', 'completed', 'cancelled', 'no_show')),
	first_name TEXT,
	last_name TEXT,
	identity_policy TEXT NOT NULL CHECK (identity_policy IN ('anonymous', 'name_required')),
	joined_at TEXT NOT NULL,
	called_at TEXT,
	started_at TEXT,
	completed_at TEXT,
	cancelled_at TEXT,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL, transition_request_id TEXT,
	UNIQUE (queue_session_id, ticket_number),
	UNIQUE (queue_session_id, queue_sequence),
	UNIQUE (queue_session_id, join_attempt_digest),
	FOREIGN KEY (organization_id, queue_id) REFERENCES queues (organization_id, id) ON DELETE RESTRICT,
	CHECK (
		(identity_policy = 'anonymous' AND first_name IS NULL AND last_name IS NULL)
		OR (identity_policy = 'name_required' AND length(trim(first_name)) > 0 AND length(trim(last_name)) > 0)
	)
);
CREATE TABLE ticket_events (
	id TEXT PRIMARY KEY,
	ticket_id TEXT NOT NULL REFERENCES tickets (id) ON DELETE RESTRICT,
	from_status TEXT CHECK (from_status IN ('waiting', 'called', 'serving', 'completed', 'cancelled', 'no_show')),
	to_status TEXT NOT NULL CHECK (to_status IN ('waiting', 'called', 'serving', 'completed', 'cancelled', 'no_show')),
	actor_type TEXT NOT NULL CHECK (actor_type IN ('visitor', 'staff', 'system')),
	actor_id TEXT,
	occurred_at TEXT NOT NULL,
	metadata TEXT,
	created_at TEXT NOT NULL
);
CREATE TABLE tracking_credentials (
	id TEXT PRIMARY KEY,
	ticket_id TEXT NOT NULL REFERENCES tickets (id) ON DELETE RESTRICT,
	token_digest TEXT NOT NULL UNIQUE,
	created_at TEXT NOT NULL,
	expires_at TEXT,
	revoked_at TEXT
);
CREATE TABLE browser_ticket_claims (
	queue_session_id TEXT NOT NULL REFERENCES queue_sessions (id) ON DELETE RESTRICT,
	ticket_id TEXT NOT NULL REFERENCES tickets (id) ON DELETE RESTRICT,
	credential_digest TEXT NOT NULL,
	created_at TEXT NOT NULL,
	PRIMARY KEY (queue_session_id, credential_digest)
);
CREATE TABLE queue_schedules (
	id TEXT PRIMARY KEY,
	organization_id TEXT NOT NULL,
	queue_id TEXT NOT NULL UNIQUE,
	enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
	weekdays TEXT NOT NULL,
	signup_open_time TEXT NOT NULL,
	service_start_time TEXT NOT NULL,
	occurrence_ticket_cap INTEGER CHECK (occurrence_ticket_cap IS NULL OR occurrence_ticket_cap > 0),
	version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
	updated_at TEXT NOT NULL,
	FOREIGN KEY (organization_id, queue_id) REFERENCES queues (organization_id, id) ON DELETE CASCADE,
	CHECK (length(weekdays) > 0)
);
DELETE FROM sqlite_sequence;
CREATE INDEX organization_memberships_by_user_status
	ON organization_memberships (user_id, status, organization_id);
CREATE INDEX locations_by_organization_active
	ON locations (organization_id, is_active, name);
CREATE INDEX services_by_location_active
	ON services (organization_id, location_id, is_active, name);
CREATE INDEX membership_location_access_by_location
	ON membership_location_access (organization_id, location_id, user_id);
CREATE INDEX membership_audit_by_subject_time
	ON membership_audit_events (organization_id, subject_user_id, created_at DESC);
CREATE INDEX sessions_by_user ON sessions (user_id);
CREATE INDEX accounts_by_user ON accounts (user_id);
CREATE UNIQUE INDEX accounts_by_provider_account ON accounts (provider_id, account_id);
CREATE INDEX verifications_by_identifier ON verifications (identifier);
CREATE INDEX staff_invitations_by_org_email
	ON staff_invitations (organization_id, invited_email, created_at DESC);
CREATE UNIQUE INDEX one_open_staff_invitation_per_email
	ON staff_invitations (organization_id, invited_email)
	WHERE accepted_at IS NULL AND revoked_at IS NULL;
CREATE INDEX queues_by_organization_location
	ON queues (organization_id, location_id, name);
CREATE UNIQUE INDEX queue_sessions_one_current_per_queue
	ON queue_sessions (queue_id)
	WHERE state IN ('open', 'paused');
CREATE INDEX queue_sessions_by_queue_opened
	ON queue_sessions (organization_id, queue_id, opened_at DESC);
CREATE UNIQUE INDEX queues_create_request_once
	ON queues (organization_id, created_by_user_id, create_request_id);
CREATE UNIQUE INDEX queues_public_id_unique
	ON queues (public_id);
CREATE UNIQUE INDEX queue_sessions_open_request_once
	ON queue_sessions (queue_id, open_request_id);
CREATE INDEX queue_session_events_by_session_time
	ON queue_session_events (session_id, occurred_at, id);
CREATE INDEX tickets_by_session_status_sequence
	ON tickets (queue_session_id, status, queue_sequence);
CREATE UNIQUE INDEX ticket_events_joined_once
	ON ticket_events (ticket_id)
	WHERE from_status IS NULL AND to_status = 'waiting' AND actor_type = 'visitor';
CREATE INDEX ticket_events_by_ticket_time
	ON ticket_events (ticket_id, occurred_at, id);
CREATE INDEX tracking_credentials_by_ticket
	ON tracking_credentials (ticket_id);
CREATE INDEX browser_ticket_claims_by_ticket
	ON browser_ticket_claims (ticket_id);
CREATE UNIQUE INDEX tickets_transition_request_unique
	ON tickets (transition_request_id)
	WHERE transition_request_id IS NOT NULL;
CREATE UNIQUE INDEX ticket_events_visitor_cancel_once
	ON ticket_events (ticket_id)
	WHERE from_status = 'waiting' AND to_status = 'cancelled' AND actor_type = 'visitor';
CREATE UNIQUE INDEX queue_sessions_schedule_occurrence_unique
	ON queue_sessions (schedule_id, occurrence_key) WHERE schedule_id IS NOT NULL;
CREATE TRIGGER staff_invitations_no_token_digest_update
BEFORE UPDATE OF token_digest ON staff_invitations
BEGIN
	SELECT RAISE(ABORT, 'invitation token digest is immutable');
END;

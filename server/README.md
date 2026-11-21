# Kewkew server

The Wisp-based Gleam server owns SQLite persistence and exposes the API used by the browser client. Wisp's Mist adapter provides the HTTP listener.

## Local development

Run commands from `server/`:

```sh
gleam deps download
gleam check
gleam test
gleam run
```

The API listens on port `4000` by default. Set `KEWKEW_PORT` to use another port. The SQLite database defaults to `priv/kewkew.sqlite3`, relative to this directory; `KEWKEW_DB_PATH` overrides the path. The schema source remains `db/database.sql`.

Wisp logs each request's status, method, and path through Erlang's standard logger. Request bodies and sign-in credentials are not included in these access logs.

## Staff sign-in

`POST /api/auth/sign-in` accepts JSON:

```json
{"email":"admin@example.com","password":"your-password"}
```

On success, the server returns the user identity and sets the `kewkew_session` cookie. The cookie is `HttpOnly`, uses `SameSite=Lax`, and is marked `Secure` for HTTPS requests. Invalid credentials return a generic `401` response.

In production, set `KEWKEW_ENV=production` and provide a stable, secret `KEWKEW_SECRET_KEY_BASE`. Local development generates an ephemeral key when none is provided.

## Invitation email

Staff invitations are sent through [Resend](https://resend.com/). Configure `RESEND_API_KEY` with a Resend API key and `RESEND_FROM_EMAIL` with a verified sender address. Set `KEWKEW_PUBLIC_APP_URL` to the public client origin (for example, `https://app.example.com`) so invitation links reach the deployed client. Missing or invalid delivery configuration is reported as a failed invite; the acceptance link is never included in the API response. Keep these values in the server environment or secret manager and never in client configuration.

Invitation delivery starts in `pending` state. A successful provider response marks it
`sent`; only sent, unexpired, unrevoked invitations can be accepted. If delivery
fails, fix the configuration or provider issue and submit the invitation again.
Creating a replacement for the same organization and email revokes the failed or
expired invitation and generates a new seven-day link. A still-valid sent or
pending invitation returns `409` instead of sending a duplicate. Old links from
replaced invitations cannot grant access.

Existing staff must sign in with the invited email before accepting. Acceptance
replaces their location assignments with those from the invitation; membership,
assignments, and acceptance state commit together or all roll back. Successful
HTTP delivery and provider rejection are tested with a mocked transport; the test
suite does not send real invitation emails.

## Organization overview

The authenticated client can load active organization memberships with `GET /api/organizations` and request one overview with `GET /api/organizations/{organization_id}`. Both endpoints require the `kewkew_session` cookie set by sign-in. Missing or expired sessions receive `401`; an organization without an active membership receives `404`.

Each overview includes the organization, the member's role, a `can_manage` flag, and locations with their active state, timezone, services, and queues. Administrators receive all locations in their organization. Operators receive only locations assigned to them; `can_manage` is false.

Bootstrap the initial administrator using the instructions in [`../docs/initial-setup.md`](../docs/initial-setup.md).

## Suspend and restore staff access

Open **Staff access** as an organization administrator to view members and choose
**Suspend access** or **Restore access**. Suspension preserves the user's identity,
credentials, location assignments, and historical queue events. It denies that
organization's pages and actions on the next API request; other organization
memberships and the sign-in session remain valid. Restoration uses the member's
current role and assignments.

`GET /api/organizations/{organization_id}/staff/members` returns the administrator-only
member list. `PATCH /api/organizations/{organization_id}/staff/members/{user_id}`
accepts a JSON boolean (`false` to suspend, `true` to restore). Both routes require
an authenticated active administrator. Attempts to suspend the last active
administrator return `409`; operators receive `403`, and unavailable organizations
or memberships receive `404`. Status changes and their audit records commit in a
single SQLite write transaction. Repeating the current status succeeds without
another audit event. No schema migration is required for these existing tables.

Invitation queries are defined in `src/sql/staff_invitation.sql` and generated into
`src/server/sql.gleam` with Parrot. The invitation module keeps authorization,
token hashing, credential creation, and transaction boundaries in Gleam; it uses
the shared Parrot/SQLight adapter for all data queries. Regeneration instructions
are in [`../docs/initial-setup.md`](../docs/initial-setup.md#regenerating-typed-sql-queries).

## Change staff roles and location assignments

In **Staff access**, choose **Edit access** beside a member, select Administrator
or Operator, and save. Operators must have at least one location in the same
organization. Administrators have access to all organization locations and keep
no individual location assignments. Editing a suspended member does not restore
access; use **Restore access** separately.

`PUT /api/organizations/{organization_id}/staff/members/{user_id}` accepts
`{"role":"operator","location_ids":["location-id"]}` (or `admin` with an empty
list). It requires an active administrator, returns a JSON acknowledgement on
success, `400` for invalid access, and `409` for demotion of the last active
administrator. Role, assignment replacement, and audit creation commit together.
The next organization or queue request uses the saved permissions. Queue sessions,
tickets, and existing history are preserved. These queries use
`src/sql/staff_members.sql`; no schema migration is required.

Existing databases are upgraded on startup. Invitation delivery requires schema
version 2, which permits the pending state; keep `db/migrations/` with the server.
See the [migration workflow](../docs/initial-setup.md#existing-database-migrations)
for backup and upgrade details. The invitation form distinguishes validation,
duplicate-invitation, provider, missing-configuration, and server failures and
prevents another submission while sending.

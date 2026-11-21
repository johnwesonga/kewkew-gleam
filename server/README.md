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

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

## Organization overview

The authenticated client can load active organization memberships with `GET /api/organizations` and request one overview with `GET /api/organizations/{organization_id}`. Both endpoints require the `kewkew_session` cookie set by sign-in. Missing or expired sessions receive `401`; an organization without an active membership receives `404`.

Each overview includes the organization, the member's role, a `can_manage` flag, and locations with their active state, timezone, services, and queues. Administrators receive all locations in their organization. Operators receive only locations assigned to them; `can_manage` is false.

Bootstrap the initial administrator using the instructions in [`../docs/initial-setup.md`](../docs/initial-setup.md).

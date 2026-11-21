# Initial server setup

The first organization is created through a trusted server-side CLI command. There is no public registration or setup form.

From the repository root, provide the initial values through the environment and run:

```sh
cd server
KEWKEW_ORGANIZATION_NAME="Example Organization" \
KEWKEW_LOCATION_NAME="Main Location" \
KEWKEW_ADMIN_NAME="Example Admin" \
KEWKEW_ADMIN_EMAIL="admin@example.com" \
KEWKEW_ADMIN_PASSWORD="use-a-unique-password-of-at-least-12-characters" \
KEWKEW_LOCATION_TIMEZONE="UTC" \
gleam run -m server/bootstrap
```

If Gleam reports an `undef` error involving `server@@main:run`, clear and rebuild the generated artifacts from `server/`, then retry:

```sh
gleam clean
gleam run -m server/bootstrap
```

`KEWKEW_DB_PATH` optionally selects the SQLite file. It defaults to `priv/kewkew.sqlite3` relative to `server/`, so the database is stored at `server/priv/kewkew.sqlite3`; generated database files are ignored by Git. The schema source remains `server/db/database.sql`. Keep the administrator password in a trusted secret manager or operator environment and do not commit it or place it in a public client configuration.

The command initializes the schema when needed and creates the organization, location, administrator credential, active admin membership, membership audit event, and one-time setup marker in a single SQLite transaction. Repeating setup after successful initialization is refused. A failure in the setup transaction rolls back all created business records.

After bootstrap, start the Wisp API server from `server/` with `gleam run`, then start the client dev server from `client/` with `gleam run -m lustre/dev`. Open the local URL printed by the client dev server and sign in with the administrator email and password supplied during bootstrap. The client sends credentials to `POST /api/auth/sign-in`; a successful response sets a 30-day `kewkew_session` cookie with `HttpOnly` and `SameSite=Lax`. Wisp adds `Secure` for HTTPS requests. Invalid email/password pairs receive the same generic `401` response.

The development API proxy in `client/gleam.toml` must point to the server's port. The default server port is `4000`; change the proxy target or set `KEWKEW_PORT` to match it.

In production, set `KEWKEW_ENV=production` and provide a stable, secret `KEWKEW_SECRET_KEY_BASE`. Local development generates an ephemeral key when none is provided.

The first administrator's credential is stored as an Argon2 password hash. Automated tests verify bootstrap setup, sign-in, repeated and concurrent bootstrap rejection, and rollback when setup fails. OLA-1 is complete.

## Regenerating typed SQL queries

Server query sources live in `server/src/sql/`; Parrot generates the committed
`server/src/server/sql.gleam` module. Visitor ticket joins, tracking, and
cancellation use `visitor_ticket.sql` through the shared SQLight adapter.
Transactions remain in the ticket module so number allocation, ticket creation,
credentials, and audit events commit or roll back together.

To regenerate against a fresh copy of the schema, run from `server/`:

```sh
sqlite3 /tmp/kewkew-parrot.sqlite3 '.read db/database.sql'
gleam run -m parrot -- --sqlite /tmp/kewkew-parrot.sqlite3
gleam format --check src test
gleam test
```

Use an unused temporary database path when the schema changes. This database is
only for query generation; the commands do not migrate the application's local
database. Commit both query sources and generated bindings after verification.

## Existing database migrations

Server startup applies numbered SQLite upgrades tracked by `PRAGMA user_version`.
Version 1 invalidates legacy sessions stored before session-token hashing. Version
2 (`server/db/migrations/002_invitation_pending.sql`) rebuilds the invitation table
inside a transaction to allow `pending` delivery while preserving invitations,
token digests, foreign keys, indexes, and the immutable-digest trigger. This fixes
invitation creation on older databases that allowed only `sent` and `failed`.
Repeated startup skips completed migrations; a failed version 2 migration rolls
back its table changes and version marker. Run the server from `server/` with the
`db/migrations/` directory present, and take a SQLite backup before applying upgrades
to an existing deployment. Updating `db/database.sql` alone does not alter existing
tables; future schema changes need a migration and preservation tests.

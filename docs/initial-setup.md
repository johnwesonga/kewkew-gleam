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

`KEWKEW_DB_PATH` optionally selects the SQLite file. It defaults to `db/kewkew.sqlite3` relative to `server/`, so the database is stored at `server/db/kewkew.sqlite3`; generated database files are ignored by Git. Keep the administrator password in a trusted secret manager or operator environment and do not commit it or place it in a public client configuration.

The command initializes the schema when needed and creates the organization, location, administrator credential, active admin membership, membership audit event, and one-time setup marker in a single SQLite transaction. Repeating setup after successful initialization is refused. A failure in the setup transaction rolls back all created business records.

After bootstrap, start the Wisp API server from `server/` with `gleam run`. Staff can sign in through `POST /api/auth/sign-in` using a JSON body containing `email` and `password`. A successful response returns the staff identity as JSON and sets a 30-day `kewkew_session` cookie with `HttpOnly` and `SameSite=Lax`; Wisp adds `Secure` for HTTPS requests. Invalid email/password pairs receive the same generic `401` response.

In production, set `KEWKEW_ENV=production` and provide a stable, secret `KEWKEW_SECRET_KEY_BASE`. Local development generates an ephemeral key when none is provided.

The first administrator's credential is stored as an Argon2 password hash. Automated tests verify bootstrap setup, sign-in, repeated and concurrent bootstrap rejection, and rollback when setup fails. OLA-1 is complete.

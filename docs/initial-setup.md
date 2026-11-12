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

The Gleam server does not yet have a normal staff sign-in flow. The bootstrap credential is stored as an Argon2 password hash, but OLA-1 remains Planned until staff authentication is implemented and the first administrator can sign in through it.

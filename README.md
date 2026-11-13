# kewkew-gleam

`kewkew-gleam` rebuilds [kewkew](https://github.com/johnwesonga/kewkew) in Gleam, with a browser client in Lustre and a server application. The product helps organizations manage virtual queues: visitors join from a link or QR code and follow a private ticket, while staff configure queues and serve visitors from a shared board.

The user stories in [`docs/`](docs/) define the product behavior and acceptance criteria. The local [`kewkew-cf`](../../cloudfare-projects/kewkew-cf) project is the current visual reference. Its interface uses a light palette with deep green accents, mint and lime highlights, rounded white cards, and responsive layouts.

## Project layout

- [`client/`](client/) — browser application, compiled to JavaScript with Lustre. It makes HTTP requests to the server. Its copied [UX mock](client/docs/ux-mock.html) is the primary screen and styling reference.
- [`server/`](server/) — Wisp HTTP server that exposes the API and owns SQLite access; includes Parrot for typed SQL bindings. The copied SQLite structure is in [`server/db/database.sql`](server/db/database.sql).
- [`shared/`](shared/) — portable Gleam domain types used by both client and server, based on the SQLite business schema.
- [`docs/`](docs/) — project documentation, design notes, and user stories, including [organization and location administration](docs/organization-location-admin-user-stories.md).

The applications are at an early stage. Implement the behavior described by the user stories and use `kewkew-cf` for visual guidance. The server is the client’s API boundary and the only application that accesses the local SQLite database.

## Project conventions

- Every user story must include accompanying unit tests.
- Mark stories `Planned` before work starts, `In Progress` while implementation or acceptance tests remain, and `Completed` only after all acceptance criteria and accompanying unit tests are implemented and verified.
- Use Parrot to generate typed Gleam query bindings from SQL queries.
- Keep the interface visually close to `kewkew-cf` where practical.
- Follow the repository instructions in [`AGENTS.md`](AGENTS.md).

## Requirements

- [Gleam](https://gleam.run/getting-started/installing/)
- Node.js or another JavaScript runtime for the client
- Erlang/OTP and SQLite for the server

## Development

Run commands from each application directory:

```sh
cd client
gleam deps download
gleam test
gleam run -m lustre/dev start
```

```sh
cd server
gleam deps download
gleam test
gleam run
```

The trusted first-run setup procedure is documented in [`docs/initial-setup.md`](docs/initial-setup.md). The Wisp server provides a staff email/password sign-in endpoint; the browser client will connect to it as its authentication flow is implemented.

## Related projects

- [kewkew](https://github.com/johnwesonga/kewkew)
- [kewkew-cf](https://github.com/johnwesonga/kewkew-cf)

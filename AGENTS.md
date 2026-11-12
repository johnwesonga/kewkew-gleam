# Repository guidance

## Project overview

This repository rebuilds [kewkew-cf](https://github.com/johnwesonga/kewkew-cf) and the original Elixir [kewkew](https://github.com/johnwesonga/kewkew) in Gleam and Lustre. The local checkouts are:

- Product source: `/Users/johnwesonga/projects/elixir/ash-projects/kewkew`
- Current UI reference: `/Users/johnwesonga/projects/cloudfare-projects/kewkew-cf`

- Use the Elixir project's `docs/` user stories and corresponding tests as the authoritative source for product behavior, domain rules, and acceptance criteria. Review relevant tests when porting a story.
- Use `kewkew-cf` as the current reference for interface styling and its rebuilt user flows. Its docs can clarify product slices, but defer to the Elixir stories and tests where behavior differs.
- Preserve product behavior while choosing idiomatic Gleam/Lustre structures; do not port Ash, Phoenix, Svelte, or Cloudflare implementation details unless this project adopts them.
- The visual direction is a light, calm interface with deep green accents, mint/lime highlights, rounded white cards, and responsive layouts. Check the reference `src/app.css` and route components for concrete patterns.
- The copied UX mock is at `client/docs/ux-mock.html`; use it as the primary screen and styling reference when implementing the client.
- The reference app covers organization and staff administration, queue configuration and schedules, visitor queue joining and private ticket tracking, and staff queue operations. Treat its scope and stories as the behavioral baseline.
- Use a local SQLite database for persistence. Keep database access behind clear modules and preserve domain invariants with schema constraints and tests; document the local database and migration workflow in `docs/` as it is implemented.
- Use the installed Parrot dependency to generate typed Gleam bindings for SQL queries. Keep query source and schema in the project's SQL files, follow Parrot's sqlc conventions, and commit generated Gleam code as appropriate for reproducible builds.
- Keep the client and server as separate applications: the browser client calls the server through HTTP APIs, and only the server accesses SQLite. Do not connect the browser client directly to the database.
- The SQLite structure copied from `kewkew-cf` currently lives in `server/db/database.sql`; treat it as the starting schema when setting up server queries and database initialization.

## Documentation

- Keep project documentation, design notes, and user stories in `docs/`.
- Update documentation when behavior, setup, or user-facing workflows change.
- User stories must state the user need and acceptance criteria.

## User stories and tests

- Every user story must be accompanied by unit tests covering its acceptance criteria.
- Add tests alongside the relevant implementation in `test/`.
- Keep tests focused on observable behavior and include relevant empty, error, and boundary states.

## Gleam and Lustre conventions

- Build application UI with Lustre and keep state transitions explicit.
- Prefer small modules with clear responsibilities.
- Preserve idiomatic Gleam formatting and types; run `gleam format` after editing Gleam files.
- Do not claim an application capability in documentation until it exists in the code.

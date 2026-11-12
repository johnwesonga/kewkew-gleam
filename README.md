# kewkew-gleam

`kewkew-gleam` is a rebuild of [kewkew-cf](https://github.com/johnwesonga/kewkew-cf) and [kewkew](https://github.com/johnwesonga/kewkew), written in [Gleam](https://gleam.run/) with [Lustre](https://hexdocs.pm/lustre/). The product helps organizations manage virtual queues: visitors join from a link or QR code and follow a private ticket, while staff configure queues and serve visitors from a shared board.

The original [Elixir `kewkew`](../../elixir/ash-projects/kewkew) project is the product and behavior reference, including its user stories and workflow tests. The local [`kewkew-cf`](../../cloudfare-projects/kewkew-cf) project is the current visual and implementation reference. Its interface uses a light, calm palette with deep green accents, mint and lime highlights, rounded white cards, and responsive layouts. Preserve that recognizable look where practical while implementing the app in Lustre.

The project is at an early stage. The current code is the Gleam package scaffold; application features and their user stories will be documented as they are implemented. The product scope covers organization and staff setup, queue configuration and scheduling, visitor joining and private ticket tracking, and staff queue operations. Preserve behavior from the Elixir user stories and tests; use `kewkew-cf` for the current visual direction and rebuilt flows.

## Project conventions

- Store project documentation and user stories in [`docs/`](docs/).
- Every user story must include accompanying unit tests.
- Use a local SQLite database for application persistence.
- Keep the interface visually close to `kewkew-cf` where the platform and Lustre allow it.
- Preserve queue behavior and acceptance criteria from the reference project's user stories; do not assume its Svelte or Cloudflare implementation details must be copied.
- Follow the repository instructions in [`AGENTS.md`](AGENTS.md) when making changes.

## Requirements

- [Gleam](https://gleam.run/getting-started/installing/)
- A JavaScript runtime (the project currently targets JavaScript)
- SQLite for local application data (the database integration is not yet implemented)

## Development

```sh
gleam deps download
gleam run
gleam test
```

Run the development server with:

```sh
gleam run -m lustre/dev
```

## Documentation

Project documentation, design notes, and user stories belong in [`docs/`](docs/). Add acceptance criteria and unit tests for each user story as it is introduced.

## Related projects

- [kewkew-cf](https://github.com/johnwesonga/kewkew-cf)
- [kewkew](https://github.com/johnwesonga/kewkew)

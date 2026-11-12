# Kewkew client

The Kewkew browser client is built with Gleam and Lustre. It provides the responsive app shell and initial staff dashboard, visitor join, ticket preview, and queue settings screens. The visual reference is [`docs/ux-mock.html`](docs/ux-mock.html).

The client will call the Kewkew server over HTTP. Queue data and actions are not connected yet; the current dashboard uses empty states and the ticket screen is explicitly a preview.

## Development

```sh
gleam deps download
gleam run -m lustre/dev
gleam test
```

Build the static client into the server's `priv/static` directory with:

```sh
gleam run -m lustre/build
```

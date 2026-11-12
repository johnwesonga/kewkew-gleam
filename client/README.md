# Kewkew client

The Kewkew browser client is built with Gleam and Lustre. It provides the responsive app shell and initial staff dashboard, visitor join, ticket preview, and queue settings screens. The visual reference is [`docs/ux-mock.html`](docs/ux-mock.html).

The client calls the Kewkew server for staff sign-in and the authenticated organization overview. Queue data and actions are not connected yet; the live queue dashboard uses empty states and the ticket screen is explicitly a preview.

When no valid session is available, the client shows a sign-in form. Successful sign-in stores the server's HTTP-only session cookie in the browser and loads the organizations available to that staff member.

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

# Client routing

The Lustre client uses [Modem](https://modem.hexdocs.pm/) to connect browser
navigation to the Lustre update loop. Route definitions and pure path conversion
live in `client/src/client/router.gleam`, which keeps the route table easy to
test without a browser.

## Routes

| Path | Screen | Access/data behavior |
| --- | --- | --- |
| `/` | Sign in | Public entry point; canonical navigation uses `/sign-in`. |
| `/sign-in` | Sign in | Public. |
| `/sign-out` | Sign in | Resolves to the sign-in screen; the staff sign-out action revokes the server session and expires its cookie. |
| `/staff` | Staff dashboard | Loads the signed-in user's organizations. |
| `/staff/organization` | Organization overview | Loads the signed-in user's organizations. |
| `/staff/settings` | Queue settings | Loads the signed-in user's organizations. |
| `/staff/ticket` | Ticket preview | Loads the signed-in user's organizations. |
| `/visitor/join` | Visitor join | Public; does not request staff organization data. |
| Other paths | Not found | Renders a not-found screen without a staff API request. |

The server remains responsible for authentication and authorization. A client
route only chooses a view; it does not grant access to protected API data. The
HTTP-only session cookie is sent with authenticated API calls, and the server
must authorize every request.

## Navigation behavior

Modem intercepts same-origin links and sends the new URI to the client as a
`RouteChanged` message without a full page reload. Button-driven navigation
uses Modem's `push` effect. Modem also handles browser Back and Forward
navigation. Successful sign-in navigates to the organization overview. When
loading organization data fails, the client returns to sign-in.

The static host must rewrite application paths such as `/staff/settings` to
the client `index.html`. The API server can continue to serve `/api` separately;
the rewrite should apply only to client navigation paths. Without this SPA
fallback, in-app navigation works but a direct URL load or refresh can return a
host-level 404 before Lustre starts.

## Adding a route

1. Add a constructor to `Route` in `client/src/client/router.gleam`.
2. Add its canonical path to `to_path` and path match to `from_path`.
3. Add the view branch in `client/src/client.gleam` and wire any navigation
   links to that typed route.
4. Decide whether entering the route should load staff organization data, and
   update `route_effect` accordingly. Keep access enforcement on the server.
5. Add unit tests in `client/test/client/router_test.gleam` for parsing and
   canonical path generation.
6. If the deployment host has explicit rewrites, ensure the new client path is
   included in its SPA fallback rule.

Run `gleam test` from `client/` after changing the route table.

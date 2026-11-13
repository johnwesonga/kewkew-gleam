# Staff sign-out user story

**Status** — Completed

Implementation and focused client and server tests are complete and verified.

## Goal

Let a signed-in staff member end their current session and leave the application in a signed-out state.

## User story

As a signed-in staff member, I want to sign out so that someone using the same browser cannot continue accessing my staff account.

## Acceptance criteria

- The server exposes `POST /api/auth/sign-out` and accepts the request without a request body.
- The server revokes the session associated with the `kewkew_session` cookie. A revoked session cannot authenticate subsequent requests, even if its token is replayed.
- The response expires the `kewkew_session` cookie using the same cookie name and path so the browser stops sending it.
- Signing out without a session cookie, or with an expired or already revoked session, succeeds idempotently and still expires the cookie.
- Requests using any method other than `POST` receive a method-not-allowed response.
- After sign-out, the client clears signed-in user state, navigates to the sign-in screen, and does not restore the signed-out session from cached state.
- Database failures while revoking a valid session return a server error; the response still clears the browser cookie so the client can return to the sign-in screen.

## Dependencies

- Staff email/password sign-in and the server-managed `kewkew_session` cookie described in [staff-admin-flow-user-stories.md](staff-admin-flow-user-stories.md).
- Server session persistence and client sign-in state management.

## Test coverage

- Verify a valid session is revoked and cannot authenticate protected requests afterward.
- Verify missing, expired, and previously revoked sessions produce a successful idempotent sign-out response and an expired cookie.
- Verify `GET` and other unsupported methods are rejected.
- Verify the client clears user state and returns to the sign-in screen after a successful sign-out.
- Verify a session-revocation database failure returns a server error.

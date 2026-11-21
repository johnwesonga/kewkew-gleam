# Personal profile

A profile belongs to the signed-in identity and is shared across its organization
memberships. This flow supports viewing the display name and sign-in email and
editing the display name. Email changes, password changes, avatar uploads, and
account deletion need separate stories and are outside this flow.

## PF-1: View my profile

**Status** — Completed

**User story** — As a signed-in user, I want to view my own profile so I can confirm
which identity I am using.

**Acceptance criteria**

- The avatar and workspace navigation link to `/staff/profile`, including on mobile.
- The page loads the current persisted name and sign-in email, including after refresh.
- Authentication is required; an expired session shows a sign-in action without personal data.
- Operators and users without active organization memberships can view their own profile.
- Loading and request failures have clear states and a retry action.
- The API exposes only the current user's public profile, without password hashes or session secrets.

## PF-2: Edit my display name

**Status** — Completed

**User story** — As a signed-in user, I want to update my display name so my account
and staff identity use my current name.

**Acceptance criteria**

- The profile form starts with the saved name; the sign-in email is read-only.
- Name input is trimmed and must contain 1–100 characters, enforced on client and server.
- Save shows progress and prevents duplicate submissions. Success confirms the save,
  updates the displayed profile and avatar, and survives refresh.
- Cancel restores the saved name. Failed saves preserve the draft and explain retry or sign-in.
- A request can update only its authenticated user's name; supplied user IDs or emails
  cannot change another identity or the sign-in address.
- Updating a name preserves credentials, sessions, memberships, assignments, and history.

## API and persistence

`GET /api/profile` returns the authenticated user's existing shared `User` contract.
`PUT /api/profile` accepts `{"name":"New name"}` and returns the updated `User`.
Both require the existing session cookie; invalid names return `400`, absent or
expired authentication returns `401`, and storage failures return `500`.
Queries live in `server/src/sql/user_profile.sql` and use generated Parrot bindings.
The existing `users` table is sufficient; no schema migration is required.

## Verification

Server acceptance tests in `server/test/server/account/profile_test.gleam` cover
profile reads, authenticated ownership, validation boundaries, storage failures,
credential/session/access preservation, and profile editing without active
organization access. Client tests in `client/test/client/profile_test.gleam` cover
view/edit/cancel states, loading/retry, failed-save drafts, session expiry, JSON
save responses, avatar identity updates, and desktop/mobile profile navigation.

Open **My profile** in workspace navigation, or select your avatar. Edit the
display name and select **Save profile**; **Cancel** restores the saved value.
The sign-in email is shown read-only. The saved name is used by the header and by
staff lists when they next load. A full page refresh reloads it from the server.

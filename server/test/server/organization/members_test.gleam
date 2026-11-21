import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/option.{None, Some}
import gleam/string
import server/authentication
import server/database
import server/http as api
import server/organization/bootstrap
import server/organization/invitations
import server/organization/members
import server/organization/overview
import server/organization/queues
import simplifile
import sqlight
import wisp
import wisp/simulate

fn seed(connection: sqlight.Connection) -> bootstrap.BootstrapResult {
  let assert Ok(created) =
    bootstrap.create(
      connection,
      bootstrap.Details(
        organization_name: "Organization",
        location_name: "Main",
        admin_name: "Admin",
        email: "admin@example.com",
        password: "correct horse battery staple",
        timezone: "UTC",
      ),
    )
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO users (id, name, email) VALUES ('operator', 'Operator', 'operator@example.com'); INSERT INTO organizations (id, name) VALUES ('other', 'Other'); INSERT INTO organization_memberships (organization_id, user_id, role, status) SELECT id, 'operator', 'operator', 'active' FROM organizations;",
      on: connection,
    )
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO membership_location_access (organization_id, user_id, location_id) VALUES (?, 'operator', ?)",
      on: connection,
      with: [
        sqlight.text(created.organization_id),
        sqlight.text(created.location_id),
      ],
      expecting: decode.dynamic,
    )
  created
}

fn with_database(
  run: fn(sqlight.Connection, bootstrap.BootstrapResult) -> Nil,
) {
  let assert Ok(connection) = database.open(":memory:", "db/database.sql")
  run(connection, seed(connection))
  let _ = sqlight.close(connection)
  Nil
}

pub fn suspension_removes_only_target_organization_access_and_restore_retains_assignments_test() {
  with_database(fn(connection, created) {
    let org = created.organization_id
    let assert Ok(Some(_)) = overview.for_user(connection, "operator", org)
    let assert Ok(Nil) =
      members.set_active(
        connection,
        created.administrator_id,
        org,
        "operator",
        False,
      )
    let assert Ok(None) = overview.for_user(connection, "operator", org)
    let assert Ok(Some(_)) = overview.for_user(connection, "operator", "other")
    let assert Error(members.NotFound) =
      members.set_active(
        connection,
        "operator",
        org,
        created.administrator_id,
        False,
      )
    let assert Ok(Nil) =
      members.set_active(
        connection,
        created.administrator_id,
        org,
        "operator",
        False,
      )
    let assert Ok(Nil) =
      members.set_active(
        connection,
        created.administrator_id,
        org,
        "operator",
        True,
      )
    let assert Ok(Some(_)) = overview.for_user(connection, "operator", org)
    let assert Ok([[location]]) =
      sqlight.query(
        "SELECT location_id FROM membership_location_access WHERE user_id = 'operator'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    let assert True = location == created.location_id
    let assert Ok([[2]]) =
      sqlight.query(
        "SELECT count(*) FROM membership_audit_events WHERE subject_user_id = 'operator' AND actor_user_id = ? AND organization_id = ? AND change_type IN ('suspended', 'reactivated') AND created_at IS NOT NULL",
        on: connection,
        with: [sqlight.text(created.administrator_id), sqlight.text(org)],
        expecting: decode.list(decode.int),
      )
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT count(*) FROM users WHERE id = 'operator'",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn last_admin_operator_and_foreign_member_requests_are_rejected_test() {
  with_database(fn(connection, created) {
    let org = created.organization_id
    let assert Error(members.LastAdministrator) =
      members.set_active(
        connection,
        created.administrator_id,
        org,
        created.administrator_id,
        False,
      )
    let assert Error(members.Forbidden) =
      members.set_active(
        connection,
        "operator",
        org,
        created.administrator_id,
        False,
      )
    let assert Error(members.Forbidden) =
      members.set_active(
        connection,
        "operator",
        org,
        created.administrator_id,
        True,
      )
    let assert Error(members.NotFound) =
      members.set_active(
        connection,
        created.administrator_id,
        "other",
        "operator",
        False,
      )
    let assert Error(members.NotFound) =
      members.set_active(
        connection,
        created.administrator_id,
        org,
        "missing",
        False,
      )
    let assert Error(members.Forbidden) =
      members.list_members(connection, "operator", org)
    let assert Ok(Nil) =
      sqlight.exec(
        "INSERT INTO users (id,name,email) VALUES ('second', 'Second', 'second@example.com')",
        on: connection,
      )
    let assert Ok(_) =
      sqlight.query(
        "INSERT INTO organization_memberships (organization_id,user_id,role,status) VALUES (?, 'second', 'admin', 'active')",
        on: connection,
        with: [sqlight.text(org)],
        expecting: decode.dynamic,
      )
    let assert Ok(Nil) =
      members.set_active(
        connection,
        created.administrator_id,
        org,
        created.administrator_id,
        False,
      )
    let assert Error(members.LastAdministrator) =
      members.set_active(connection, "second", org, "second", False)
    Nil
  })
}

pub fn failed_audit_rolls_back_suspension_test() {
  with_database(fn(connection, created) {
    let assert Ok(Nil) =
      sqlight.exec(
        "CREATE TRIGGER reject_audit BEFORE INSERT ON membership_audit_events BEGIN SELECT RAISE(ABORT, 'test'); END",
        on: connection,
      )
    let assert Error(members.DatabaseFailure(_)) =
      members.set_active(
        connection,
        created.administrator_id,
        created.organization_id,
        "operator",
        False,
      )
    let assert Ok(Some(_)) =
      overview.for_user(connection, "operator", created.organization_id)
    Nil
  })
}

pub fn invitation_cannot_demote_last_active_admin_test() {
  with_database(fn(connection, created) {
    let assert Ok(invite) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "admin@example.com",
        "operator",
        [created.location_id],
      )
    let assert Ok(Nil) =
      invitations.set_delivery_state(connection, invite.id, "sent")
    let assert Error(invitations.InvalidOrExpired) =
      invitations.accept_for_user(
        connection,
        invite.token,
        created.administrator_id,
      )
    let assert Ok([["admin"]]) =
      sqlight.query(
        "SELECT role FROM organization_memberships WHERE user_id = ?",
        on: connection,
        with: [sqlight.text(created.administrator_id)],
        expecting: decode.list(decode.string),
      )
    Nil
  })
}

pub fn member_http_routes_require_auth_and_report_conflicts_test() {
  with_database(fn(connection, created) {
    let context =
      api.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost",
      )
    let path =
      "/api/organizations/" <> created.organization_id <> "/staff/members"
    let unauthorized = simulate.request(http.Get, path) |> api.handle(context)
    let assert 401 = unauthorized.status
    let assert Ok(session) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let listed =
      simulate.request(http.Get, path)
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> api.handle(context)
    let assert 200 = listed.status
    let assert wisp.Text(body) = listed.body
    let assert True = string.contains(body, "operator@example.com")
    let assert False = string.contains(body, "password")
    let conflict =
      simulate.request(http.Patch, path <> "/" <> created.administrator_id)
      |> simulate.string_body("false")
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> api.handle(context)
    let assert 409 = conflict.status
    let suspended =
      simulate.request(http.Patch, path <> "/operator")
      |> simulate.string_body("false")
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> api.handle(context)
    let assert 200 = suspended.status
    let restored =
      simulate.request(http.Patch, path <> "/operator")
      |> simulate.string_body("true")
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> api.handle(context)
    let assert 200 = restored.status
    Nil
  })
}

type WorkerMessage {
  Ready(process.Subject(Nil))
  Finished(Result(Nil, members.MemberError))
}

pub fn concurrent_suspensions_cannot_remove_all_administrators_test() {
  let filename =
    crypto.strong_random_bytes(16) |> bit_array.base64_url_encode(False)
  let path = "/tmp/kewkew-members-" <> filename <> ".sqlite3"
  let assert Ok(connection) = database.open(path, "db/database.sql")
  let created = seed(connection)
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO users (id,name,email) VALUES ('second','Second','second@example.com')",
      on: connection,
    )
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO organization_memberships (organization_id,user_id,role,status) VALUES (?, 'second', 'admin', 'active')",
      on: connection,
      with: [sqlight.text(created.organization_id)],
      expecting: decode.dynamic,
    )
  let _ = sqlight.close(connection)
  let messages = process.new_subject()
  let run = fn(actor) {
    let assert Ok(connection) = database.open(path, "db/database.sql")
    let start = process.new_subject()
    process.send(messages, Ready(start))
    let assert Ok(Nil) = process.receive(start, 5000)
    let outcome =
      members.set_active(
        connection,
        actor,
        created.organization_id,
        actor,
        False,
      )
    let _ = sqlight.close(connection)
    process.send(messages, Finished(outcome))
  }
  let _ = process.spawn_unlinked(fn() { run(created.administrator_id) })
  let _ = process.spawn_unlinked(fn() { run("second") })
  let assert Ok(Ready(first)) = process.receive(messages, 10_000)
  let assert Ok(Ready(second)) = process.receive(messages, 10_000)
  process.send(first, Nil)
  process.send(second, Nil)
  let assert Ok(Finished(first_result)) = process.receive(messages, 10_000)
  let assert Ok(Finished(second_result)) = process.receive(messages, 10_000)
  let assert True = case first_result, second_result {
    Ok(Nil), Error(members.LastAdministrator)
    | Error(members.LastAdministrator), Ok(Nil)
    -> True
    _, _ -> False
  }
  let assert Ok(connection) = database.open(path, "db/database.sql")
  let assert Ok([[1]]) =
    sqlight.query(
      "SELECT count(*) FROM organization_memberships WHERE role = 'admin' AND status = 'active'",
      on: connection,
      with: [],
      expecting: decode.list(decode.int),
    )
  let _ = sqlight.close(connection)
  let _ = simplifile.delete(path)
  Nil
}

pub fn existing_session_loses_staff_pages_and_queue_actions_without_losing_history_test() {
  with_database(fn(connection, created) {
    let org = created.organization_id
    let admin = created.administrator_id
    let assert Ok(session) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let assert Ok(_) =
      sqlight.query(
        "UPDATE organization_memberships SET role = 'admin' WHERE organization_id = ? AND user_id = 'operator'",
        on: connection,
        with: [sqlight.text(org)],
        expecting: decode.dynamic,
      )
    let assert Ok(_) =
      sqlight.query(
        "INSERT INTO services (id,organization_id,location_id,name) VALUES ('history-service',?,?, 'History')",
        on: connection,
        with: [sqlight.text(org), sqlight.text(created.location_id)],
        expecting: decode.dynamic,
      )
    let assert Ok(_) =
      sqlight.query(
        "INSERT INTO queues (id,organization_id,location_id,service_id,name,identity_policy) VALUES ('history-queue',?,?, 'history-service','History','anonymous')",
        on: connection,
        with: [sqlight.text(org), sqlight.text(created.location_id)],
        expecting: decode.dynamic,
      )
    let assert Ok(_) =
      sqlight.query(
        "INSERT INTO queue_sessions (id,organization_id,queue_id,state,opened_at,closed_at) VALUES ('history-session',?,'history-queue','closed','2026-01-01T00:00:00Z','2026-01-01T01:00:00Z')",
        on: connection,
        with: [sqlight.text(org)],
        expecting: decode.dynamic,
      )
    let assert Ok(_) =
      sqlight.query(
        "INSERT INTO tickets (id,organization_id,queue_id,queue_session_id,ticket_number,queue_sequence,join_attempt_digest,status,identity_policy,joined_at,created_at,updated_at) VALUES ('history-ticket',?,'history-queue','history-session',1,1,'history-digest','completed','anonymous','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','2026-01-01T00:30:00Z')",
        on: connection,
        with: [sqlight.text(org)],
        expecting: decode.dynamic,
      )
    let assert Ok(_) =
      sqlight.query(
        "INSERT INTO ticket_events (id,ticket_id,from_status,to_status,actor_type,actor_id,occurred_at,created_at) VALUES ('history-event','history-ticket','serving','completed','staff',?,'2026-01-01T00:30:00Z','2026-01-01T00:30:00Z')",
        on: connection,
        with: [sqlight.text(admin)],
        expecting: decode.dynamic,
      )
    let assert Ok(Nil) =
      members.set_active(connection, "operator", org, admin, False)
    let context =
      api.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost",
      )
    let page =
      simulate.request(http.Get, "/api/organizations/" <> org)
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> api.handle(context)
    let assert 404 = page.status
    let assert Error(queues.NotFound) =
      queues.open_session(
        connection,
        admin,
        org,
        created.location_id,
        "history-service",
        "history-queue",
      )
    let assert Ok(_) =
      authentication.user_for_session(connection, session.token)
    let assert Ok(Nil) =
      members.set_active(connection, "operator", org, admin, True)
    let page =
      simulate.request(http.Get, "/api/organizations/" <> org)
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> api.handle(context)
    let assert 200 = page.status
    let assert Ok([[actor]]) =
      sqlight.query(
        "SELECT actor_id FROM ticket_events WHERE id = 'history-event' AND occurred_at = '2026-01-01T00:30:00Z'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    let assert True = actor == admin
    let assert Ok([["completed"]]) =
      sqlight.query(
        "SELECT status FROM tickets WHERE id = 'history-ticket'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    Nil
  })
}

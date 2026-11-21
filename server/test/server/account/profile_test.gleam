import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/string
import server/account/profile
import server/authentication
import server/database
import server/http as api
import server/organization/bootstrap
import server/organization/invitations
import shared/json as shared_json
import sqlight
import wisp
import wisp/simulate

fn with_database(
  run: fn(sqlight.Connection, bootstrap.BootstrapResult, String) -> Nil,
) {
  let assert Ok(connection) = database.open(":memory:", "db/database.sql")
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
  let assert Ok(session) =
    authentication.sign_in(
      connection,
      "admin@example.com",
      "correct horse battery staple",
    )
  run(connection, created, session.token)
  let _ = sqlight.close(connection)
  Nil
}

fn context(connection: sqlight.Connection) -> api.Context {
  api.Context(
    database: connection,
    resend_api_key: "",
    resend_from: "",
    public_app_url: "http://localhost",
  )
}

fn update_request(
  connection: sqlight.Connection,
  token: String,
  body: String,
) -> wisp.Response {
  simulate.request(http.Put, "/api/profile")
  |> simulate.string_body(body)
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
  |> api.handle(context(connection))
}

pub fn profile_get_and_update_persist_name_without_changing_credentials_or_access_test() {
  with_database(fn(connection, created, token) {
    let assert Ok(before) =
      sqlight.query(
        "SELECT json_array((SELECT password FROM accounts LIMIT 1), (SELECT json_group_array(json_array(organization_id,user_id,role,status,updated_at)) FROM organization_memberships), (SELECT json_group_array(json_array(id,token,expires_at)) FROM sessions), (SELECT count(*) FROM membership_audit_events))",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    let changed =
      update_request(
        connection,
        token,
        "{\"name\":\"  Alex Morgan  \",\"id\":\"another-user\",\"email\":\"changed@example.com\"}",
      )
    let assert 200 = changed.status
    let assert wisp.Text(body) = changed.body
    let assert Ok(user) = json.parse(body, shared_json.user_decoder())
    let assert True = user.id == created.administrator_id
    let assert "Alex Morgan" = user.name
    let assert "admin@example.com" = user.email
    let assert False = string.contains(body, "password")
    let assert False = string.contains(body, "token")
    let assert False = string.contains(body, "created_at")
    let refreshed =
      simulate.request(http.Get, "/api/profile")
      |> simulate.cookie("kewkew_session", token, wisp.PlainText)
      |> api.handle(context(connection))
    let assert 200 = refreshed.status
    let assert wisp.Text(refreshed_body) = refreshed.body
    let assert True = refreshed_body == body
    let assert Ok(after) =
      sqlight.query(
        "SELECT json_array((SELECT password FROM accounts LIMIT 1), (SELECT json_group_array(json_array(organization_id,user_id,role,status,updated_at)) FROM organization_memberships), (SELECT json_group_array(json_array(id,token,expires_at)) FROM sessions), (SELECT count(*) FROM membership_audit_events))",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    let assert True = before == after
    let assert Ok(_) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    Nil
  })
}

pub fn profile_validation_rejects_empty_long_and_malformed_names_without_writes_test() {
  with_database(fn(connection, created, token) {
    let assert 400 =
      update_request(connection, token, "{\"name\":\"   \"}").status
    let assert 400 = update_request(connection, token, "{}").status
    let assert 400 = update_request(connection, token, "{\"name\":7}").status
    let long_name = string.repeat("x", 101)
    let assert Error(profile.InvalidName) =
      profile.update_name(connection, created.administrator_id, long_name)
    let assert Ok(user) = profile.get(connection, created.administrator_id)
    let assert "Admin" = user.name
    let assert Ok(boundary) =
      profile.update_name(
        connection,
        created.administrator_id,
        string.repeat("x", 100),
      )
    let assert 100 = string.length(boundary.name)
    let assert Ok(single) =
      profile.update_name(connection, created.administrator_id, "  A  ")
    let assert "A" = single.name
    Nil
  })
}

pub fn profile_requires_unexpired_authentication_and_rejects_other_methods_test() {
  with_database(fn(connection, _, token) {
    let unauthenticated =
      simulate.request(http.Get, "/api/profile")
      |> api.handle(context(connection))
    let assert 401 = unauthenticated.status
    let update =
      simulate.request(http.Put, "/api/profile")
      |> simulate.string_body("{\"name\":\"Attack\"}")
      |> api.handle(context(connection))
    let assert 401 = update.status
    let assert Ok(Nil) =
      sqlight.exec(
        "UPDATE sessions SET expires_at = '2000-01-01T00:00:00Z'",
        on: connection,
      )
    let assert 401 =
      update_request(connection, token, "{\"name\":\"Expired\"}").status
    let other =
      simulate.request(http.Delete, "/api/profile")
      |> api.handle(context(connection))
    let assert 405 = other.status
    Nil
  })
}

pub fn operator_can_edit_only_own_profile_even_without_active_organization_access_test() {
  with_database(fn(connection, created, _) {
    let assert Ok(invite) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "operator@example.com",
        "operator",
        [created.location_id],
      )
    let assert Ok(Nil) =
      invitations.set_delivery_state(connection, invite.id, "sent")
    let assert Ok(Nil) =
      invitations.accept(
        connection,
        invite.token,
        "Operator",
        "operator secure password",
      )
    let assert Ok(session) =
      authentication.sign_in(
        connection,
        "operator@example.com",
        "operator secure password",
      )
    let assert Ok(_) =
      sqlight.query(
        "UPDATE organization_memberships SET status = 'suspended' WHERE user_id = ?",
        on: connection,
        with: [sqlight.text(session.user.id)],
        expecting: decode.dynamic,
      )
    let result =
      update_request(
        connection,
        session.token,
        "{\"name\":\"Updated Operator\",\"user_id\":\""
          <> created.administrator_id
          <> "\"}",
      )
    let assert 200 = result.status
    let assert Ok(operator) = profile.get(connection, session.user.id)
    let assert "Updated Operator" = operator.name
    let assert Ok(admin) = profile.get(connection, created.administrator_id)
    let assert "Admin" = admin.name
    Nil
  })
}

pub fn failed_profile_write_returns_error_and_preserves_saved_name_test() {
  with_database(fn(connection, created, token) {
    let assert Ok(Nil) =
      sqlight.exec(
        "CREATE TRIGGER reject_name BEFORE UPDATE OF name ON users BEGIN SELECT RAISE(ABORT, 'test failure'); END",
        on: connection,
      )
    let result = update_request(connection, token, "{\"name\":\"Failed\"}")
    let assert 500 = result.status
    let assert Ok(user) = profile.get(connection, created.administrator_id)
    let assert "Admin" = user.name
    Nil
  })
}

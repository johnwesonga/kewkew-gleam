import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/http as gleam_http
import gleam/http/request as http_request
import gleam/list
import gleam/string
import server/authentication
import server/database
import server/http as server_http
import server/organization/bootstrap
import server/organization/invitations
import simplifile
import sqlight
import wisp
import wisp/simulate

pub fn accepts_bootstrapped_credentials_and_creates_session_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(session) =
      authentication.sign_in(
        connection,
        " ADMIN@example.com ",
        "correct horse battery staple",
      )

    let assert True = session.user.id == created.administrator_id
    let assert True = session.user.name == "Test Admin"
    let assert True = session.user.email == "admin@example.com"
    let assert True = string.length(session.token) >= 40
    let assert Ok([[1]]) = count(connection, "sessions")
    let assert Ok([[stored_token]]) =
      sqlight.query(
        "SELECT token FROM sessions WHERE user_id = ?",
        on: connection,
        with: [sqlight.text(created.administrator_id)],
        expecting: decode.list(decode.string),
      )
    let assert True = stored_token == token_digest(session.token)
    let assert False = stored_token == session.token
    Nil
  })
}

pub fn rejects_incorrect_password_without_creating_session_test() {
  with_database(fn(connection) {
    let assert Ok(_) = bootstrap.create(connection, details())
    let assert Error(authentication.InvalidCredentials) =
      authentication.sign_in(connection, "admin@example.com", "incorrect")
    let assert Ok([[0]]) = count(connection, "sessions")
    Nil
  })
}

pub fn invitation_acceptance_creates_identity_membership_and_location_access_once_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(invitation) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "operator@example.com",
        "operator",
        [created.location_id],
      )
    let assert Ok(Nil) =
      invitations.set_delivery_state(connection, invitation.id, "sent")
    let assert Ok(invitation_list) =
      invitations.list_sent(
        connection,
        created.administrator_id,
        created.organization_id,
      )
    let assert True = string.contains(invitation_list, "operator@example.com")
    let assert True = string.contains(invitation_list, "operator")
    let assert False = string.contains(invitation_list, "token_digest")
    let assert False = string.contains(invitation_list, invitation.token)
    let assert True = string.length(invitation.token) >= 40
    let assert Ok([[stored_digest]]) =
      sqlight.query(
        "SELECT token_digest FROM staff_invitations WHERE id = ?",
        on: connection,
        with: [sqlight.text(invitation.id)],
        expecting: decode.list(decode.string),
      )
    let assert False = stored_digest == invitation.token
    let assert Ok(Nil) =
      invitations.accept(
        connection,
        invitation.token,
        "New Operator",
        "a very long test password",
      )
    let assert Ok([[2]]) = count(connection, "users")
    let assert Ok([[1]]) = count(connection, "membership_location_access")
    let assert Ok([["operator"]]) =
      sqlight.query(
        "SELECT role FROM organization_memberships WHERE organization_id = ? AND user_id = (SELECT id FROM users WHERE email = 'operator@example.com')",
        on: connection,
        with: [sqlight.text(created.organization_id)],
        expecting: decode.list(decode.string),
      )
    let assert Error(invitations.InvalidOrExpired) =
      invitations.accept(
        connection,
        invitation.token,
        "New Operator",
        "a very long test password",
      )
    Nil
  })
}

pub fn invalid_operator_invitation_is_rejected_without_persisting_it_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Error(invitations.InvalidInvitation) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "operator@example.com",
        "operator",
        [],
      )
    let assert Ok([[0]]) = count(connection, "staff_invitations")
    Nil
  })
}

pub fn failed_delivery_invitation_cannot_be_accepted_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(invitation) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "pending@example.com",
        "admin",
        [],
      )
    let assert Error(invitations.InvalidOrExpired) =
      invitations.accept(
        connection,
        invitation.token,
        "Invitee",
        "a very long test password",
      )
    let assert Error(invitations.InvalidOrExpired) =
      invitations.accept(
        connection,
        invitation.token,
        "Invitee",
        "a very long test password",
      )
    Nil
  })
}

pub fn existing_identity_acceptance_reactivates_membership_without_duplicate_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(invitation) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "admin@example.com",
        "admin",
        [],
      )
    let assert Ok(Nil) =
      invitations.set_delivery_state(connection, invitation.id, "sent")
    let assert Ok(Nil) =
      execute(
        connection,
        "UPDATE organization_memberships SET status = 'suspended' WHERE organization_id = ? AND user_id = ?",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.administrator_id),
        ],
      )

    let assert Ok(Nil) =
      invitations.accept_for_user(
        connection,
        invitation.token,
        created.administrator_id,
      )

    let assert Ok([[1]]) = count(connection, "users")
    let assert Ok([[1]]) = count(connection, "organization_memberships")
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM membership_audit_events WHERE organization_id = ? AND subject_user_id = ? AND change_type = 'invitation_accepted'",
        on: connection,
        with: [
          sqlight.text(created.organization_id),
          sqlight.text(created.administrator_id),
        ],
        expecting: decode.list(decode.int),
      )
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM organization_memberships WHERE organization_id = ? AND user_id = ? AND role = 'admin' AND status = 'active'",
        on: connection,
        with: [
          sqlight.text(created.organization_id),
          sqlight.text(created.administrator_id),
        ],
        expecting: decode.list(decode.int),
      )
    let assert Error(invitations.InvalidOrExpired) =
      invitations.accept_for_user(
        connection,
        invitation.token,
        created.administrator_id,
      )
    Nil
  })
}

pub fn existing_identity_cannot_accept_invitation_for_another_email_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(invitation) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "operator@example.com",
        "operator",
        [created.location_id],
      )
    let assert Ok(Nil) =
      invitations.set_delivery_state(connection, invitation.id, "sent")

    let assert Error(invitations.InvalidOrExpired) =
      invitations.accept_for_user(
        connection,
        invitation.token,
        created.administrator_id,
      )
    let assert Ok([[0]]) = count(connection, "membership_location_access")
    let assert Ok([[1]]) = count(connection, "users")
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM staff_invitations WHERE id = ? AND accepted_at IS NOT NULL",
        on: connection,
        with: [sqlight.text(invitation.id)],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn expired_invitation_cannot_be_accepted_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(invitation) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "operator@example.com",
        "operator",
        [created.location_id],
      )
    let assert Ok(Nil) =
      invitations.set_delivery_state(connection, invitation.id, "sent")
    let assert Ok(Nil) =
      execute(
        connection,
        "UPDATE staff_invitations SET expires_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 second') WHERE id = ?",
        [sqlight.text(invitation.id)],
      )

    let assert Error(invitations.InvalidOrExpired) =
      invitations.accept(
        connection,
        invitation.token,
        "Expired Operator",
        "a very long test password",
      )
    let assert Ok([[1]]) = count(connection, "users")
    let assert Ok([[0]]) = count(connection, "membership_location_access")
    Nil
  })
}

pub fn existing_account_acceptance_route_requires_auth_and_accepts_session_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(invitation) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "admin@example.com",
        "admin",
        [],
      )
    let assert Ok(Nil) =
      invitations.set_delivery_state(connection, invitation.id, "sent")
    let body = <<"{\"token\":\"":utf8, invitation.token:utf8, "\"}":utf8>>
    let request =
      json_request(gleam_http.Post, "/api/invitations/accept-existing", body)
    let unauthorized =
      request
      |> server_http.handle(test_context(connection))
    let assert 401 = unauthorized.status

    let assert Ok(session) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let response =
      json_request(gleam_http.Post, "/api/invitations/accept-existing", body)
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> server_http.handle(test_context(connection))
    let assert 200 = response.status
    let assert Ok([[1]]) = count(connection, "users")
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM staff_invitations WHERE id = ? AND accepted_at IS NOT NULL AND accepted_by_user_id = ?",
        on: connection,
        with: [
          sqlight.text(invitation.id),
          sqlight.text(created.administrator_id),
        ],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn invitation_create_api_requires_admin_and_marks_missing_delivery_config_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let body = <<
      "{\"email\":\"operator@example.com\",\"role\":\"operator\",\"location_ids\":[\"":utf8,
      created.location_id:utf8,
      "\"]}":utf8,
    >>
    let path =
      "/api/organizations/" <> created.organization_id <> "/staff/invitations"
    let unauthenticated =
      json_request(gleam_http.Post, path, body)
      |> server_http.handle(test_context(connection))
    let assert 401 = unauthenticated.status
    let assert Ok([[0]]) = count(connection, "staff_invitations")

    let assert Ok(session) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let response =
      json_request(gleam_http.Post, path, body)
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> server_http.handle(test_context(connection))
    let assert 503 = response.status
    let assert Ok([[1]]) = count(connection, "staff_invitations")
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM staff_invitations WHERE invited_email = 'operator@example.com' AND delivery_state = 'failed'",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn staff_invitation_list_api_is_admin_only_and_hides_tokens_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(operator_invitation) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "operator@example.com",
        "operator",
        [created.location_id],
      )
    let assert Ok(Nil) =
      invitations.set_delivery_state(connection, operator_invitation.id, "sent")
    let assert Ok(admin_invitation) =
      invitations.create(
        connection,
        created.administrator_id,
        created.organization_id,
        "another-admin@example.com",
        "admin",
        [],
      )
    let assert Ok(Nil) =
      invitations.set_delivery_state(connection, admin_invitation.id, "sent")

    let assert Ok(admin_session) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let path =
      "/api/organizations/" <> created.organization_id <> "/staff/invitations"
    let admin_response =
      simulate.request(gleam_http.Get, path)
      |> simulate.cookie("kewkew_session", admin_session.token, wisp.PlainText)
      |> server_http.handle(test_context(connection))
    let assert 200 = admin_response.status
    let assert wisp.Text(invitation_list) = admin_response.body
    let assert True = string.contains(invitation_list, "operator@example.com")
    let assert True =
      string.contains(invitation_list, "another-admin@example.com")
    let assert False =
      string.contains(invitation_list, operator_invitation.token)
    let assert False = string.contains(invitation_list, admin_invitation.token)

    let assert Ok(Nil) =
      invitations.accept(
        connection,
        operator_invitation.token,
        "New Operator",
        "a very long test password",
      )
    let assert Ok(operator_session) =
      authentication.sign_in(
        connection,
        "operator@example.com",
        "a very long test password",
      )
    let operator_response =
      simulate.request(gleam_http.Get, path)
      |> simulate.cookie(
        "kewkew_session",
        operator_session.token,
        wisp.PlainText,
      )
      |> server_http.handle(test_context(connection))
    let assert 403 = operator_response.status
    Nil
  })
}

pub fn sign_out_revokes_session_and_is_idempotent_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(session) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let assert Ok(Nil) = authentication.sign_out(connection, session.token)
    let assert Error(authentication.InvalidCredentials) =
      authentication.user_for_session(connection, session.token)
    let assert Ok(Nil) = authentication.sign_out(connection, session.token)
    let assert Ok([[0]]) = count(connection, "sessions")
    let assert True = created.administrator_id == session.user.id
    Nil
  })
}

pub fn sign_out_route_expires_cookie_and_revokes_valid_session_test() {
  with_database(fn(connection) {
    let assert Ok(_) = bootstrap.create(connection, details())
    let assert Ok(session) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let response =
      simulate.request(gleam_http.Post, "/api/auth/sign-out")
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert True = response.status == 200
    let assert Ok(cookie) = list.key_find(response.headers, "set-cookie")
    let assert True = string.contains(cookie, "kewkew_session=")
    let assert True = string.contains(cookie, "Max-Age=0")
    let assert True = string.contains(cookie, "Path=/")
    let assert True = string.contains(cookie, "HttpOnly")
    let assert Error(authentication.InvalidCredentials) =
      authentication.user_for_session(connection, session.token)
    Nil
  })
}

pub fn sign_out_without_cookie_succeeds_and_expires_cookie_test() {
  with_database(fn(connection) {
    let response =
      simulate.request(gleam_http.Post, "/api/auth/sign-out")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert True = response.status == 200
    let assert Ok(cookie) = list.key_find(response.headers, "set-cookie")
    let assert True = string.contains(cookie, "Max-Age=0")
    Nil
  })
}

pub fn sign_out_only_accepts_post_test() {
  with_database(fn(connection) {
    let response =
      simulate.request(gleam_http.Get, "/api/auth/sign-out")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert True = response.status == 405
    Nil
  })
}

pub fn returns_session_in_http_only_cookie_not_json_body_test() {
  with_database(fn(connection) {
    let assert Ok(_) = bootstrap.create(connection, details())
    let body = <<
      "{\"email\":\"admin@example.com\",\"password\":\"correct horse battery staple\"}":utf8,
    >>
    let response =
      create_sign_in_request(body)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert True = response.status == 200
    let assert Ok("no-store") = list.key_find(response.headers, "cache-control")
    let assert Ok(cookie) = list.key_find(response.headers, "set-cookie")
    let assert True = string.contains(cookie, "HttpOnly")
    let assert True = string.contains(cookie, "SameSite=Lax")
    let assert True = string.contains(cookie, "Secure")
    let assert True = string.contains(cookie, "kewkew_session=")
    let assert wisp.Text(response_text) = response.body
    let assert False =
      string.contains(response_text, "correct horse battery staple")
    let assert False = string.contains(response_text, "kewkew_session=")
    Nil
  })
}

pub fn invalid_bootstrapped_credentials_return_unauthorized_without_session_test() {
  with_database(fn(connection) {
    let assert Ok(_) = bootstrap.create(connection, details())
    let body = <<
      "{\"email\":\"admin@example.com\",\"password\":\"incorrect\"}":utf8,
    >>
    let response =
      create_sign_in_request(body)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert True = response.status == 401
    let assert wisp.Text(response_text) = response.body
    let assert True =
      response_text == "{\"error\":\"invalid email or password\"}"
    let assert Error(Nil) = list.key_find(response.headers, "set-cookie")
    let assert Ok([[0]]) = count(connection, "sessions")
    Nil
  })
}

pub fn invalid_sign_in_json_returns_bad_request_test() {
  with_database(fn(connection) {
    let body = <<"{invalid json":utf8>>
    let response =
      create_sign_in_request(body)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert True = response.status == 400
    let assert Ok([[0]]) = count(connection, "sessions")
    Nil
  })
}

pub fn oversized_sign_in_body_returns_413_without_creating_session_test() {
  with_database(fn(connection) {
    let body = string.repeat("x", times: 16_385) |> bit_array.from_string
    let response =
      create_sign_in_request(body)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert True = response.status == 413
    let assert Ok([[0]]) = count(connection, "sessions")
    Nil
  })
}

fn create_sign_in_request(body: BitArray) -> wisp.Request {
  simulate.request(gleam_http.Post, "/api/auth/sign-in")
  |> simulate.bit_array_body(body)
  |> http_request.set_header("content-type", "application/json")
}

fn json_request(
  method: gleam_http.Method,
  path: String,
  body: BitArray,
) -> wisp.Request {
  simulate.request(method, path)
  |> simulate.bit_array_body(body)
  |> http_request.set_header("content-type", "application/json")
}

fn test_context(connection: sqlight.Connection) -> server_http.Context {
  server_http.Context(
    database: connection,
    resend_api_key: "",
    resend_from: "",
    public_app_url: "http://localhost:8080",
  )
}

fn token_digest(token: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(token))
  |> bit_array.base16_encode
}

fn with_database(run: fn(sqlight.Connection) -> Nil) -> Nil {
  let assert Ok(connection) = sqlight.open(":memory:")
  let assert Ok(schema) = simplifile.read("db/database.sql")
  let assert Ok(Nil) = database.initialize(connection, schema)
  run(connection)
  let _ = sqlight.close(connection)
  Nil
}

fn count(
  connection: sqlight.Connection,
  table: String,
) -> Result(List(List(Int)), sqlight.Error) {
  sqlight.query(
    "SELECT COUNT(*) FROM " <> table,
    on: connection,
    with: [],
    expecting: decode.list(decode.int),
  )
}

fn execute(
  connection: sqlight.Connection,
  statement: String,
  parameters: List(sqlight.Value),
) -> Result(Nil, sqlight.Error) {
  case
    sqlight.query(
      statement <> " RETURNING 'ok'",
      on: connection,
      with: parameters,
      expecting: decode.list(decode.string),
    )
  {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(error)
  }
}

fn details() -> bootstrap.Details {
  bootstrap.Details(
    organization_name: "Test Organization",
    location_name: "Main",
    admin_name: "Test Admin",
    email: "admin@example.com",
    password: "correct horse battery staple",
    timezone: "UTC",
  )
}

import gleam/bit_array
import gleam/dynamic/decode
import gleam/http as gleam_http
import gleam/http/request as http_request
import gleam/list
import gleam/string
import server/authentication
import server/database
import server/http as server_http
import server/organization/bootstrap
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
    let assert True = stored_token == session.token
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
      |> server_http.handle(server_http.Context(database: connection))
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
      |> server_http.handle(server_http.Context(database: connection))
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
      |> server_http.handle(server_http.Context(database: connection))
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
      |> server_http.handle(server_http.Context(database: connection))
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
      |> server_http.handle(server_http.Context(database: connection))
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
      |> server_http.handle(server_http.Context(database: connection))
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
      |> server_http.handle(server_http.Context(database: connection))
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

import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/result
import server/authentication
import sqlight
import wisp

const max_sign_in_body_bytes = 16_384

pub type Context {
  Context(database: sqlight.Connection)
}

/// Handle the API routes currently implemented by the server.
pub fn handle(request: wisp.Request, context: Context) -> wisp.Response {
  case request.path {
    "/api/auth/sign-in" ->
      case request.method {
        http.Post -> sign_in(request, context)
        _ -> wisp.method_not_allowed([http.Post])
      }
    "/health" ->
      case request.method {
        http.Get -> json_response(200, "{\"status\":\"ok\"}")
        _ -> wisp.method_not_allowed([http.Get])
      }
    _ -> wisp.json_response(error_json("not found"), 404)
  }
}

fn sign_in(request: wisp.Request, context: Context) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case parse_credentials(body) {
      Error(_) -> json_response(400, error_json("invalid sign-in request"))
      Ok(#(email, password)) ->
        authentication.sign_in(context.database, email, password)
        |> sign_in_response(request)
    }
  })
}

fn sign_in_response(
  result: Result(authentication.Session, authentication.SignInError),
  request: wisp.Request,
) -> wisp.Response {
  case result {
    Ok(session) -> sign_in_success(request, session)
    Error(authentication.InvalidCredentials) ->
      json_response(401, error_json("invalid email or password"))
    Error(authentication.DatabaseFailure(_)) ->
      json_response(500, error_json("sign-in could not be completed"))
  }
}

fn parse_credentials(body: BitArray) -> Result(#(String, String), Nil) {
  json.parse_bits(body, credentials_decoder()) |> result.replace_error(Nil)
}

fn sign_in_success(
  request: wisp.Request,
  session: authentication.Session,
) -> wisp.Response {
  let user =
    json.object([
      #("id", json.string(session.user.id)),
      #("name", json.string(session.user.name)),
      #("email", json.string(session.user.email)),
    ])
  json_response(200, json.to_string(json.object([#("user", user)])))
  |> wisp.set_cookie(
    request,
    "kewkew_session",
    session.token,
    wisp.PlainText,
    30 * 24 * 60 * 60,
  )
}

fn credentials_decoder() -> decode.Decoder(#(String, String)) {
  use email <- decode.field("email", decode.string)
  use password <- decode.field("password", decode.string)
  decode.success(#(email, password))
}

fn error_json(message: String) -> String {
  json.object([#("error", json.string(message))]) |> json.to_string
}

fn json_response(status: Int, body: String) -> wisp.Response {
  wisp.json_response(body, status)
  |> wisp.set_header("cache-control", "no-store")
}

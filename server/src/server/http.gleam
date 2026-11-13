import gleam/dynamic/decode
import gleam/http
import gleam/http/cookie
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import server/authentication
import server/organization/overview
import server/organization/profile
import sqlight
import wisp

const max_sign_in_body_bytes = 16_384

pub type Context {
  Context(database: sqlight.Connection)
}

/// Handle the API routes currently implemented by the server.
pub fn handle(request: wisp.Request, context: Context) -> wisp.Response {
  use <- wisp.log_request(request)
  case request.path {
    "/api/auth/sign-in" ->
      case request.method {
        http.Post -> sign_in(request, context)
        _ -> wisp.method_not_allowed([http.Post])
      }
    "/api/auth/sign-out" ->
      case request.method {
        http.Post -> sign_out(request, context)
        _ -> wisp.method_not_allowed([http.Post])
      }
    "/api/organizations" ->
      case request.method {
        http.Get -> list_organizations(request, context)
        _ -> wisp.method_not_allowed([http.Get])
      }
    "/health" ->
      case request.method {
        http.Get -> json_response(200, "{\"status\":\"ok\"}")
        _ -> wisp.method_not_allowed([http.Get])
      }
    _ -> organization_detail(request, context)
  }
}

fn organization_detail(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
  case string.split(request.path, "/") {
    ["", "api", "organizations", organization_id] ->
      case request.method {
        http.Get ->
          with_authenticated_user(request, context, fn(user_id) {
            case overview.for_user(context.database, user_id, organization_id) {
              Ok(Some(body)) -> json_response(200, body)
              Ok(None) -> json_response(404, error_json("not found"))
              Error(_) ->
                json_response(500, error_json("request could not be completed"))
            }
          })
        http.Put ->
          request
          |> wisp.set_max_body_size(max_sign_in_body_bytes)
          |> wisp.require_bit_array_body(fn(body) {
            case parse_organization_name(body) {
              Error(_) ->
                json_response(400, error_json("invalid organization name"))
              Ok(name) ->
                with_authenticated_user(request, context, fn(user_id) {
                  case
                    profile.update_name(
                      context.database,
                      user_id,
                      organization_id,
                      name,
                    )
                  {
                    Ok(Nil) ->
                      case
                        overview.for_user(
                          context.database,
                          user_id,
                          organization_id,
                        )
                      {
                        Ok(Some(response_body)) ->
                          json_response(200, response_body)
                        Ok(None) -> json_response(404, error_json("not found"))
                        Error(_) ->
                          json_response(
                            500,
                            error_json("request could not be completed"),
                          )
                      }
                    Error(profile.InvalidName) ->
                      json_response(
                        400,
                        error_json("organization name is required"),
                      )
                    Error(profile.Forbidden) ->
                      json_response(
                        403,
                        error_json("administrator access required"),
                      )
                    Error(profile.NotFound) ->
                      json_response(404, error_json("not found"))
                    Error(profile.DatabaseFailure(_)) ->
                      json_response(
                        500,
                        error_json("request could not be completed"),
                      )
                  }
                })
            }
          })
        _ -> wisp.method_not_allowed([http.Get, http.Put])
      }
    _ -> wisp.json_response(error_json("not found"), 404)
  }
}

fn list_organizations(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
  with_authenticated_user(request, context, fn(user_id) {
    case overview.list_for_user(context.database, user_id) {
      Ok(organizations) ->
        json_response(200, "[" <> string.join(organizations, ",") <> "]")
      Error(_) ->
        json_response(500, error_json("request could not be completed"))
    }
  })
}

fn with_authenticated_user(
  request: wisp.Request,
  context: Context,
  respond: fn(String) -> wisp.Response,
) -> wisp.Response {
  case wisp.get_cookie(request, "kewkew_session", wisp.PlainText) {
    Error(Nil) -> json_response(401, error_json("authentication required"))
    Ok(token) ->
      case authentication.user_for_session(context.database, token) {
        Ok(user_id) -> respond(user_id)
        Error(authentication.InvalidCredentials) ->
          json_response(401, error_json("authentication required"))
        Error(authentication.DatabaseFailure(_)) ->
          json_response(500, error_json("request could not be completed"))
      }
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

fn sign_out(request: wisp.Request, context: Context) -> wisp.Response {
  let response = json_response(200, "{\"status\":\"ok\"}")
  let response = case
    wisp.get_cookie(request, "kewkew_session", wisp.PlainText)
  {
    Ok(token) ->
      case authentication.sign_out(context.database, token) {
        Ok(Nil) -> response
        Error(_) ->
          json_response(500, error_json("sign-out could not be completed"))
      }
    Error(Nil) -> response
  }
  let scheme = case request.host {
    "localhost" | "127.0.0.1" | "[::1]" if request.scheme == http.Http ->
      case request.get_header(request, "x-forwarded-proto") {
        Ok(_) -> http.Https
        Error(_) -> http.Http
      }
    _ -> http.Https
  }
  response
  |> response.expire_cookie("kewkew_session", cookie.defaults(scheme))
  |> wisp.set_header("cache-control", "no-store")
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

fn parse_organization_name(body: BitArray) -> Result(String, Nil) {
  json.parse_bits(body, organization_name_decoder())
  |> result.replace_error(Nil)
}

fn organization_name_decoder() -> decode.Decoder(String) {
  use name <- decode.field("name", decode.string)
  decode.success(name)
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
      #("image", json.null()),
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

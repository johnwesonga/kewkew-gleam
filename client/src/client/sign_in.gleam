import gleam/dynamic/decode
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect, none}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared
import shared/json as shared_json

pub type Model {
  Model(email: String, password: String, pending: Bool, error: Option(String))
}

pub type Message {
  EmailChanged(String)
  PasswordChanged(String)
  Submit
  SignedIn(Result(shared.User, rsvp.Error(String)))
  SignOut
  SignedOut(Result(Response(String), rsvp.Error(String)))
  SessionExpired
}

pub fn init() -> Model {
  Model(email: "", password: "", pending: False, error: None)
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    EmailChanged(email) -> #(Model(..model, email:, error: None), none())
    PasswordChanged(password) -> #(
      Model(..model, password:, error: None),
      none(),
    )
    Submit -> submit(model)
    SignedIn(Ok(_)) -> #(
      Model(..model, password: "", pending: False, error: None),
      none(),
    )
    SignedIn(Error(_)) -> #(
      Model(
        ..model,
        pending: False,
        error: Some(
          "We couldn't sign you in. Check your email and password and try again.",
        ),
      ),
      none(),
    )
    SignOut -> #(
      model,
      rsvp.post(
        "/api/auth/sign-out",
        json.null(),
        rsvp.expect_ok_response(SignedOut),
      ),
    )
    SignedOut(_) -> #(model, effect.none())
    SessionExpired -> #(
      Model(..model, error: Some("Your session expired. Please sign in again.")),
      none(),
    )
  }
}

fn submit(model: Model) -> #(Model, Effect(Message)) {
  case
    model.pending,
    string.trim(model.email) == "",
    string.trim(model.password) == ""
  {
    True, _, _ -> #(model, effect.none())
    False, True, _ -> #(
      Model(..model, error: Some("Enter your email address.")),
      none(),
    )
    False, _, True -> #(
      Model(..model, error: Some("Enter your password.")),
      effect.none(),
    )
    False, False, False -> #(
      Model(..model, pending: True, error: None),
      rsvp.post(
        "/api/auth/sign-in",
        json.object([
          #("email", json.string(model.email)),
          #("password", json.string(model.password)),
        ]),
        rsvp.expect_json(signed_in_user_decoder(), SignedIn),
      ),
    )
  }
}

fn signed_in_user_decoder() -> decode.Decoder(shared.User) {
  use user <- decode.field("user", shared_json.user_decoder())
  decode.success(user)
}

pub fn view(
  email: String,
  password: String,
  pending: Bool,
  error: Option(String),
  on_email_input: fn(String) -> message,
  on_password_input: fn(String) -> message,
  on_submit: message,
) -> Element(message) {
  html.main([attr.class("sign-in-shell")], [
    html.section([attr.class("sign-in-card card")], [
      html.div([attr.class("brand sign-in-brand")], [
        html.span([attr.class("brand-mark")], [html.text("k")]),
        html.span([], [
          html.text("Kewkew"),
          html.small([], [html.text("Queue, without the wait")]),
        ]),
      ]),
      html.p([attr.class("eyebrow")], [html.text("Staff workspace")]),
      html.h1([], [html.text("Sign in")]),
      html.p([attr.class("subhead")], [
        html.text("Use your organization account to continue."),
      ]),
      html.form([event.on_submit(fn(_) { on_submit })], [
        html.label(
          [attr.class("field"), attr.attribute("for", "sign-in-email")],
          [
            html.text("Email address"),
            html.input([
              attr.attribute("id", "sign-in-email"),
              attr.attribute("name", "email"),
              attr.attribute("type", "email"),
              attr.attribute("autocomplete", "username"),
              attr.attribute("placeholder", "you@example.com"),
              attr.attribute("value", email),
              attr.required(True),
              event.on_input(on_email_input),
            ]),
          ],
        ),
        html.label(
          [attr.class("field"), attr.attribute("for", "sign-in-password")],
          [
            html.text("Password"),
            html.input([
              attr.attribute("id", "sign-in-password"),
              attr.attribute("name", "password"),
              attr.attribute("type", "password"),
              attr.attribute("autocomplete", "current-password"),
              attr.attribute("placeholder", "Enter your password"),
              attr.attribute("value", password),
              attr.required(True),
              event.on_input(on_password_input),
            ]),
          ],
        ),
        case error {
          Some(message) ->
            html.p(
              [attr.class("sign-in-error"), attr.attribute("role", "alert")],
              [html.text(message)],
            )
          _ -> element.none()
        },
        html.button(
          [
            attr.class("primary full-width sign-in-submit"),
            attr.attribute("type", "submit"),
            attr.disabled(pending),
          ],
          [
            html.text(case pending {
              True -> "Signing in…"
              False -> "Sign in"
            }),
          ],
        ),
      ]),
      html.p([attr.class("privacy-note")], [
        html.text("Your session is protected by a secure, HTTP-only cookie."),
      ]),
    ]),
  ])
}

import gleam/option.{type Option, Some}
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

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

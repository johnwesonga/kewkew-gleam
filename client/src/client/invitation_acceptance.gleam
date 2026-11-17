import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element, none}
import lustre/element/html
import lustre/event
import rsvp

pub type Model {
  Model(
    token: Option(String),
    name: String,
    password: String,
    status: Option(String),
  )
}

pub type Message {
  NameChanged(String)
  PasswordChanged(String)
  Submit
  Submitted(Result(String, rsvp.Error(String)))
}

pub fn init() -> Model {
  Model(None, "", "", None)
}

pub fn update(
  model: Model,
  token: Option(String),
  message: Message,
) -> #(Model, Effect(Message)) {
  case message {
    NameChanged(name) -> #(Model(..model, name:, status: None), effect.none())
    PasswordChanged(password) -> #(
      Model(..model, password:, status: None),
      effect.none(),
    )
    Submit -> submit(model, token)
    Submitted(Ok(_)) -> #(
      Model(
        ..model,
        status: Some("Your account is ready. You can now sign in."),
      ),
      effect.none(),
    )
    Submitted(Error(_)) -> #(
      Model(
        ..model,
        status: Some(
          "We couldn't accept this invitation. It may have expired or already been used.",
        ),
      ),
      effect.none(),
    )
  }
}

fn submit(model: Model, token: Option(String)) -> #(Model, Effect(Message)) {
  case token {
    None -> #(
      Model(..model, status: Some("This invitation link is missing its token.")),
      effect.none(),
    )
    Some(token) ->
      case
        string.length(model.password) >= 12 && string.trim(model.name) != ""
      {
        False -> #(
          Model(
            ..model,
            status: Some(
              "Enter your name and a password with at least 12 characters.",
            ),
          ),
          effect.none(),
        )
        True -> #(
          model,
          rsvp.post(
            "/api/invitations/accept",
            json.object([
              #("token", json.string(token)),
              #("name", json.string(string.trim(model.name))),
              #("password", json.string(model.password)),
            ]),
            rsvp.expect_json(status_decoder(), Submitted),
          ),
        )
      }
  }
}

fn status_decoder() -> decode.Decoder(String) {
  use status <- decode.field("status", decode.string)
  decode.success(status)
}

pub fn view(
  model: Model,
  token: Option(String),
  lift: fn(Message) -> message,
) -> Element(message) {
  html.main([attr.class("invitation-shell")], [
    html.header([attr.class("invitation-brand")], [
      html.a([attr.class("brand"), attr.attribute("href", "/")], [
        html.span([attr.class("brand-mark")], [html.text("k")]),
        html.span([], [
          html.text("Kewkew"),
          html.small([], [html.text("Queue, without the wait")]),
        ]),
      ]),
      html.span([attr.class("invitation-secure-label")], [
        html.span([attr.attribute("aria-hidden", "true")], [html.text("●")]),
        html.text(" Secure staff setup"),
      ]),
    ]),
    html.div([attr.class("invitation-content")], [
      html.div([attr.class("invitation-intro")], [
        html.div([attr.class("invitation-icon")], [html.text("✦")]),
        html.p([attr.class("eyebrow")], [html.text("Staff invitation")]),
        html.h1([], [html.text("Set up your staff account")]),
        html.p([attr.class("subhead")], [
          html.text("Create your sign-in details to join your team on Kewkew."),
        ]),
      ]),
      html.section([attr.class("invitation-form-card card")], [
        html.div([attr.class("invitation-form-heading")], [
          html.h2([], [html.text("Your account details")]),
          html.p([], [html.text("Use a password you have not used elsewhere.")]),
        ]),
        html.form(
          [
            attr.class("invitation-form"),
            event.on_submit(fn(_) { lift(Submit) }),
          ],
          [
            html.label([attr.class("field")], [
              html.text("Full name"),
              html.input([
                attr.attribute("autocomplete", "name"),
                attr.attribute("placeholder", "Your name"),
                attr.attribute("value", model.name),
                attr.required(True),
                event.on_input(fn(value) { lift(NameChanged(value)) }),
              ]),
            ]),
            html.label([attr.class("field")], [
              html.text("Create password"),
              html.input([
                attr.attribute("type", "password"),
                attr.attribute("autocomplete", "new-password"),
                attr.attribute("placeholder", "At least 12 characters"),
                attr.attribute("value", model.password),
                attr.attribute("minlength", "12"),
                attr.required(True),
                event.on_input(fn(value) { lift(PasswordChanged(value)) }),
              ]),
            ]),
            html.p([attr.class("invitation-password-hint")], [
              html.span([attr.attribute("aria-hidden", "true")], [
                html.text("✓"),
              ]),
              html.text(" Use at least 12 characters."),
            ]),
            html.button(
              [
                attr.class("primary invitation-submit"),
                attr.attribute("type", "submit"),
              ],
              [
                html.text("Create account and accept invitation"),
                html.span([attr.attribute("aria-hidden", "true")], [
                  html.text("→"),
                ]),
              ],
            ),
          ],
        ),
        case model.status {
          Some(status) ->
            html.p(
              [
                attr.class("invitation-feedback"),
                attr.attribute("role", "status"),
              ],
              [html.text(status)],
            )
          None -> none()
        },
        case token {
          None ->
            html.p(
              [
                attr.class("invitation-feedback invitation-error"),
                attr.attribute("role", "alert"),
              ],
              [
                html.text("Invitation token not found in this link."),
              ],
            )
          Some(_) -> none()
        },
      ]),
      html.p([attr.class("invitation-expiry-note")], [
        html.text("This single-use invitation link expires after seven days."),
      ]),
    ]),
    html.footer([attr.class("invitation-footer")], [
      html.text("© Kewkew · Secure queue management for your team"),
    ]),
  ])
}

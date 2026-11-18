import gleam/dynamic/decode
import gleam/http/response.{type Response}
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
    existing_account: Bool,
    email: String,
    name: String,
    password: String,
    pending: Bool,
    accepted: Bool,
    status: Option(String),
  )
}

pub type Message {
  NameChanged(String)
  PasswordChanged(String)
  EmailChanged(String)
  UseExistingAccount
  UseNewAccount
  Submit
  SubmitExistingAccount
  Submitted(Result(String, rsvp.Error(String)))
  SignInCompleted(Result(Response(String), rsvp.Error(String)))
  ExistingInvitationAccepted(Result(String, rsvp.Error(String)))
}

pub fn init() -> Model {
  Model(None, False, "", "", "", False, False, None)
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
    EmailChanged(email) -> #(
      Model(..model, email:, status: None),
      effect.none(),
    )
    UseExistingAccount -> #(
      Model(..model, existing_account: True, status: None),
      effect.none(),
    )
    UseNewAccount -> #(
      Model(..model, existing_account: False, status: None),
      effect.none(),
    )
    Submit -> submit(model, token)
    SubmitExistingAccount -> submit_existing_account(model, token)
    Submitted(Ok(_)) -> #(
      Model(
        ..model,
        pending: False,
        status: Some("Your account is ready. You can now sign in."),
      ),
      effect.none(),
    )
    Submitted(Error(_)) -> #(
      Model(
        ..model,
        pending: False,
        status: Some(
          "We couldn't accept this invitation. It may have expired or already been used.",
        ),
      ),
      effect.none(),
    )
    SignInCompleted(Ok(response)) if response.status == 200 ->
      accept_for_existing_user(model, token)
    SignInCompleted(_) -> #(
      Model(
        ..model,
        pending: False,
        status: Some("We couldn't sign you in. Check your email and password."),
      ),
      effect.none(),
    )
    ExistingInvitationAccepted(Ok(_)) -> #(
      Model(
        ..model,
        pending: False,
        accepted: True,
        status: Some("Invitation accepted. Your account now has staff access."),
      ),
      effect.none(),
    )
    ExistingInvitationAccepted(Error(_)) -> #(
      Model(
        ..model,
        pending: False,
        status: Some(
          "We couldn't accept this invitation. It may be invalid, expired, or already used.",
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
        !model.pending
        && string.length(model.password) >= 12
        && string.trim(model.name) != ""
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
          Model(..model, pending: True, status: None),
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

fn submit_existing_account(
  model: Model,
  token: Option(String),
) -> #(Model, Effect(Message)) {
  case token {
    None -> #(
      Model(..model, status: Some("This invitation link is missing its token.")),
      effect.none(),
    )
    Some(_) ->
      case model.pending {
        True -> #(model, effect.none())
        False ->
          case
            string.trim(model.email) == "",
            string.trim(model.password) == ""
          {
            True, _ -> #(
              Model(..model, status: Some("Enter your email address.")),
              effect.none(),
            )
            _, True -> #(
              Model(..model, status: Some("Enter your password.")),
              effect.none(),
            )
            False, False -> #(
              Model(..model, pending: True, status: None),
              rsvp.post(
                "/api/auth/sign-in",
                json.object([
                  #("email", json.string(model.email)),
                  #("password", json.string(model.password)),
                ]),
                rsvp.expect_any_response(SignInCompleted),
              ),
            )
          }
      }
  }
}

fn accept_for_existing_user(
  model: Model,
  token: Option(String),
) -> #(Model, Effect(Message)) {
  case token {
    None -> #(
      Model(
        ..model,
        pending: False,
        status: Some("This invitation link is missing its token."),
      ),
      effect.none(),
    )
    Some(token) -> #(
      model,
      rsvp.post(
        "/api/invitations/accept-existing",
        json.object([#("token", json.string(token))]),
        rsvp.expect_json(status_decoder(), ExistingInvitationAccepted),
      ),
    )
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
          html.text(case model.existing_account {
            True ->
              "Sign in to the invited account to join your team on Kewkew."
            False -> "Create sign-in details to join your team on Kewkew."
          }),
        ]),
      ]),
      html.section([attr.class("invitation-form-card card")], [
        html.div([attr.class("invitation-form-heading")], [
          html.h2([], [
            html.text(case model.existing_account {
              True -> "Sign in to accept"
              False -> "Your account details"
            }),
          ]),
          html.p([], [
            html.text(case model.existing_account {
              True -> "Sign in with the account invited to join this team."
              False -> "Create sign-in details to join your team on Kewkew."
            }),
          ]),
        ]),
        case model.accepted {
          True ->
            html.a(
              [
                attr.class("primary invitation-submit"),
                attr.attribute("href", "/staff"),
              ],
              [html.text("Go to your staff workspace →")],
            )
          False ->
            case model.existing_account {
              False ->
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
                        event.on_input(fn(value) {
                          lift(PasswordChanged(value))
                        }),
                      ]),
                    ]),
                    html.p([attr.class("invitation-password-hint")], [
                      html.span(
                        [
                          attr.attribute("aria-hidden", "true"),
                        ],
                        [html.text("✓")],
                      ),
                      html.text(" Use at least 12 characters."),
                    ]),
                    html.button(
                      [
                        attr.class("primary invitation-submit"),
                        attr.attribute("type", "submit"),
                        attr.disabled(model.pending),
                      ],
                      [
                        html.text(case model.pending {
                          True -> "Creating account…"
                          False -> "Create account and accept invitation →"
                        }),
                      ],
                    ),
                  ],
                )
              True ->
                html.form(
                  [
                    attr.class("invitation-form"),
                    event.on_submit(fn(_) { lift(SubmitExistingAccount) }),
                  ],
                  [
                    html.label([attr.class("field")], [
                      html.text("Email address"),
                      html.input([
                        attr.attribute("type", "email"),
                        attr.attribute("autocomplete", "username"),
                        attr.attribute("placeholder", "you@example.com"),
                        attr.attribute("value", model.email),
                        attr.required(True),
                        event.on_input(fn(value) { lift(EmailChanged(value)) }),
                      ]),
                    ]),
                    html.label([attr.class("field")], [
                      html.text("Password"),
                      html.input([
                        attr.attribute("type", "password"),
                        attr.attribute("autocomplete", "current-password"),
                        attr.attribute("value", model.password),
                        attr.required(True),
                        event.on_input(fn(value) {
                          lift(PasswordChanged(value))
                        }),
                      ]),
                    ]),
                    html.button(
                      [
                        attr.class("primary invitation-submit"),
                        attr.attribute("type", "submit"),
                        attr.disabled(model.pending),
                      ],
                      [
                        html.text(case model.pending {
                          True -> "Signing in and accepting…"
                          False -> "Sign in and accept invitation →"
                        }),
                      ],
                    ),
                  ],
                )
            }
        },
        case model.accepted {
          True -> none()
          False ->
            html.button(
              [
                attr.class("invitation-mode-switch"),
                attr.attribute("type", "button"),
                event.on_click(
                  lift(case model.existing_account {
                    True -> UseNewAccount
                    False -> UseExistingAccount
                  }),
                ),
              ],
              [
                html.text(case model.existing_account {
                  True -> "New to Kewkew? Create an account instead."
                  False -> "Already have an account? Sign in to accept."
                }),
              ],
            )
        },
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

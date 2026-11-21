import client/navigation
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared.{type User}
import shared/json as shared_json

pub type Model {
  Model(
    user: Option(User),
    name: String,
    loading: Bool,
    pending: Bool,
    error: Option(String),
    notice: Option(String),
    session_expired: Bool,
  )
}

pub type Message {
  Load
  Loaded(Result(User, rsvp.Error(String)))
  NameChanged(String)
  Save
  Saved(Result(User, rsvp.Error(String)))
  Cancel
}

pub fn init() -> Model {
  Model(None, "", True, False, None, None, False)
}

pub fn load() -> Effect(Message) {
  rsvp.get("/api/profile", rsvp.expect_json(shared_json.user_decoder(), Loaded))
}

pub fn save_handler() -> rsvp.Handler(String, Message) {
  rsvp.expect_json(shared_json.user_decoder(), Saved)
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    Load ->
      case model.pending {
        True -> #(model, effect.none())
        False -> #(init(), load())
      }
    Loaded(Ok(user)) -> #(
      Model(Some(user), user.name, False, False, None, None, False),
      effect.none(),
    )
    Loaded(Error(error)) -> #(
      Model(
        ..init(),
        loading: False,
        error: Some(error_message(error)),
        session_expired: expired(error),
      ),
      effect.none(),
    )
    NameChanged(name) ->
      case model.pending {
        True -> #(model, effect.none())
        False -> #(
          Model(..model, name:, error: None, notice: None),
          effect.none(),
        )
      }
    Cancel ->
      case model.user, model.pending {
        Some(user), False -> #(
          Model(..model, name: user.name, error: None, notice: None),
          effect.none(),
        )
        _, _ -> #(model, effect.none())
      }
    Save ->
      case model.user, model.pending {
        Some(_), False -> {
          let name = string.trim(model.name)
          case string.length(name) >= 1 && string.length(name) <= 100 {
            False -> #(
              Model(
                ..model,
                error: Some("Enter a name containing 1 to 100 characters."),
                notice: None,
              ),
              effect.none(),
            )
            True -> #(
              Model(..model, pending: True, error: None, notice: None),
              rsvp.put(
                "/api/profile",
                json.object([#("name", json.string(name))]),
                save_handler(),
              ),
            )
          }
        }
        _, _ -> #(model, effect.none())
      }
    Saved(Ok(user)) -> #(
      Model(
        Some(user),
        user.name,
        False,
        False,
        None,
        Some("Your profile has been updated."),
        False,
      ),
      effect.none(),
    )
    Saved(Error(error)) ->
      case expired(error) {
        True -> #(
          Model(None, "", False, False, Some(error_message(error)), None, True),
          effect.none(),
        )
        False -> #(
          Model(
            ..model,
            pending: False,
            error: Some(error_message(error)),
            notice: None,
          ),
          effect.none(),
        )
      }
  }
}

pub fn updated_user(message: Message) -> Option(User) {
  case message {
    Loaded(Ok(user)) | Saved(Ok(user)) -> Some(user)
    _ -> None
  }
}

fn expired(error: rsvp.Error(String)) -> Bool {
  case error {
    rsvp.HttpError(response) if response.status == 401 -> True
    _ -> False
  }
}

fn error_message(error: rsvp.Error(String)) -> String {
  case error {
    rsvp.HttpError(response) if response.status == 401 ->
      "Your session has expired. Sign in to view or edit your profile."
    rsvp.HttpError(response) if response.status == 400 ->
      "Enter a name containing 1 to 100 characters."
    _ -> "We could not load or save your profile. Please try again."
  }
}

pub fn view(model: Model, lift: fn(Message) -> message) -> Element(message) {
  html.section([attr.class("page profile-page")], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Your account")]),
        html.h1([], [html.text("My profile")]),
        html.p([attr.class("subhead")], [
          html.text("View your account and keep your display name up to date."),
        ]),
      ]),
    ]),
    html.section([attr.class("card personal-profile-card")], [
      case model.loading {
        True ->
          html.p([attr.attribute("role", "status")], [
            html.text("Loading your profile…"),
          ])
        False ->
          case model.user {
            None ->
              html.div([], [
                case model.session_expired {
                  True ->
                    html.a(
                      [
                        attr.class("primary profile-sign-in"),
                        attr.href("/sign-in"),
                      ],
                      [html.text("Sign in")],
                    )
                  False ->
                    html.button(
                      [attr.class("secondary"), event.on_click(lift(Load))],
                      [html.text("Try again")],
                    )
                },
              ])
            Some(user) ->
              html.form([event.on_submit(fn(_) { lift(Save) })], [
                html.div([attr.class("personal-profile-summary")], [
                  navigation.avatar(Some(user)),
                  html.div([], [
                    html.h2([], [html.text(user.name)]),
                    html.p([], [html.text(user.email)]),
                  ]),
                ]),
                html.label([attr.class("field")], [
                  html.span([], [html.text("Display name")]),
                  html.input([
                    attr.name("name"),
                    attr.type_("text"),
                    attr.value(model.name),
                    attr.required(True),
                    attr.attribute("maxlength", "100"),
                    attr.attribute("autocomplete", "name"),
                    attr.disabled(model.pending),
                    event.on_input(fn(name) { lift(NameChanged(name)) }),
                  ]),
                ]),
                html.label([attr.class("field")], [
                  html.span([], [html.text("Sign-in email")]),
                  html.input([
                    attr.type_("email"),
                    attr.value(user.email),
                    attr.readonly(True),
                    attr.attribute("aria-describedby", "profile-email-note"),
                  ]),
                ]),
                html.p([attr.id("profile-email-note"), attr.class("muted")], [
                  html.text(
                    "Your sign-in email is managed separately and cannot be changed here.",
                  ),
                ]),
                html.div([attr.class("personal-profile-actions")], [
                  html.button(
                    [
                      attr.class("primary"),
                      attr.type_("submit"),
                      attr.disabled(model.pending),
                    ],
                    [
                      html.text(case model.pending {
                        True -> "Saving…"
                        False -> "Save profile"
                      }),
                    ],
                  ),
                  html.button(
                    [
                      attr.class("secondary"),
                      attr.type_("button"),
                      attr.disabled(model.pending),
                      event.on_click(lift(Cancel)),
                    ],
                    [html.text("Cancel")],
                  ),
                ]),
              ])
          }
      },
      case model.error {
        Some(error) ->
          html.p(
            [attr.class("sign-in-error"), attr.attribute("role", "alert")],
            [html.text(error)],
          )
        None -> html.text("")
      },
      case model.notice {
        Some(notice) ->
          html.p(
            [attr.class("profile-success"), attr.attribute("role", "status")],
            [html.text(notice)],
          )
        None -> html.text("")
      },
    ]),
  ])
}

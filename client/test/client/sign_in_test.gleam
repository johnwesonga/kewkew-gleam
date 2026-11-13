import client/router
import client/sign_in
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/element
import shared

pub fn sign_in_form_has_email_and_password_fields_test() {
  let markup = render(None, False)
  let assert True = string.contains(markup, "Staff workspace")
  let assert True = string.contains(markup, "Email address")
  let assert True = string.contains(markup, "type=\"email\"")
  let assert True = string.contains(markup, "autocomplete=\"username\"")
  let assert True = string.contains(markup, "Password")
  let assert True = string.contains(markup, "type=\"password\"")
  let assert True = string.contains(markup, "current-password")
  let assert True = string.contains(markup, "type=\"submit\"")
}

pub fn sign_in_form_displays_generic_error_accessibly_test() {
  let markup = render(Some("We couldn't sign you in. Try again."), False)
  let assert True = string.contains(markup, "role=\"alert\"")
  let assert True = string.contains(markup, "Try again.")
}

pub fn sign_in_form_disables_submit_while_pending_test() {
  let markup = render(None, True)
  let assert True = string.contains(markup, "Signing in…")
  let assert True = string.contains(markup, "disabled")
}

pub fn sign_out_returns_to_sign_in_route_test() {
  assert router.from_path("/sign-out") == router.SignIn
}

pub fn empty_sign_in_submission_shows_validation_error_test() {
  let #(model, _) = sign_in.update(sign_in.init(), sign_in.Submit)
  let assert Some(message) = model.error
  let assert True = string.contains(message, "Enter your email address")
}

pub fn successful_sign_in_clears_password_and_error_test() {
  let model =
    sign_in.Model(
      email: "admin@example.com",
      password: "secret",
      pending: True,
      error: Some("old error"),
    )
  let #(updated, _) =
    sign_in.update(
      model,
      sign_in.SignedIn(
        Ok(shared.User(
          id: "user-1",
          name: "Admin",
          email: "admin@example.com",
          image: None,
        )),
      ),
    )
  let assert True = updated.password == ""
  let assert False = updated.pending
  let assert None = updated.error
}

fn render(error: Option(String), pending: Bool) -> String {
  sign_in.view(
    "admin@example.com",
    "password-value",
    pending,
    error,
    fn(_) { Nil },
    fn(_) { Nil },
    Nil,
  )
  |> element.to_string
}

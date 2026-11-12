import client/sign_in
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/element

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

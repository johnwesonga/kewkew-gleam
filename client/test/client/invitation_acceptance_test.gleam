import client/invitation_acceptance
import gleam/option.{None, Some}
import gleam/string
import lustre/element

pub fn invitation_setup_uses_kewkew_brand_and_onboarding_layout_test() {
  let markup =
    invitation_acceptance.view(
      invitation_acceptance.init(),
      Some("invite-token"),
      fn(message) { message },
    )
    |> element.to_string
  let assert True = string.contains(markup, "Kewkew")
  let assert True = string.contains(markup, "brand-mark")
  let assert True = string.contains(markup, "Secure staff setup")
  let assert True = string.contains(markup, "invitation-content")
  let assert True = string.contains(markup, "invitation-form-card card")
  let assert True =
    string.contains(markup, "Create account and accept invitation")
  let assert True = string.contains(markup, "single-use invitation link")
}

pub fn missing_invitation_token_is_shown_as_an_accessible_error_test() {
  let markup =
    invitation_acceptance.view(invitation_acceptance.init(), None, fn(message) {
      message
    })
    |> element.to_string
  let assert True = string.contains(markup, "role=\"alert\"")
  let assert True = string.contains(markup, "Invitation token not found")
}

pub fn existing_account_sign_in_path_is_available_test() {
  let #(model, _) =
    invitation_acceptance.update(
      invitation_acceptance.init(),
      Some("invite-token"),
      invitation_acceptance.UseExistingAccount,
    )
  let markup =
    invitation_acceptance.view(model, Some("invite-token"), fn(message) {
      message
    })
    |> element.to_string
  let assert True = string.contains(markup, "Sign in to accept")
  let assert True = string.contains(markup, "Email address")
  let assert True = string.contains(markup, "Sign in and accept invitation")
  let assert False =
    string.contains(markup, "Create account and accept invitation")
}

pub fn existing_account_acceptance_shows_success_and_workspace_link_test() {
  let #(model, _) =
    invitation_acceptance.update(
      invitation_acceptance.init(),
      Some("invite-token"),
      invitation_acceptance.ExistingInvitationAccepted(Ok("accepted")),
    )
  let markup =
    invitation_acceptance.view(model, Some("invite-token"), fn(message) {
      message
    })
    |> element.to_string
  let assert True = string.contains(markup, "Your account now has staff access")
  let assert True = string.contains(markup, "Go to your staff workspace")
}

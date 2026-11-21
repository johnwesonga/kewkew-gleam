import client/navigation
import client/profile
import client/router
import gleam/http/response
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/dev/simulate
import lustre/effect
import lustre/element
import rsvp
import shared

fn user() -> shared.User {
  shared.User("self", "Alex Morgan", "alex@example.com", None)
}

fn loaded() -> profile.Model {
  profile.update(profile.init(), profile.Loaded(Ok(user()))).0
}

pub fn profile_view_shows_saved_name_readonly_email_and_edit_actions_test() {
  let markup =
    profile.view(loaded(), fn(message) { message }) |> element.to_string
  string.contains(markup, "Alex Morgan") |> should.be_true
  string.contains(markup, "alex@example.com") |> should.be_true
  string.contains(markup, "readonly") |> should.be_true
  string.contains(markup, "Display name") |> should.be_true
  string.contains(markup, "Save profile") |> should.be_true
  string.contains(markup, "Cancel") |> should.be_true
}

pub fn profile_validation_cancel_and_duplicate_save_states_test() {
  let #(blank, _) = profile.update(loaded(), profile.NameChanged("  "))
  let #(invalid, pending) = profile.update(blank, profile.Save)
  pending |> should.equal(effect.none())
  invalid.pending |> should.be_false
  let assert Some(_) = invalid.error
  let #(long, _) =
    profile.update(loaded(), profile.NameChanged(string.repeat("x", 101)))
  let #(invalid, _) = profile.update(long, profile.Save)
  let assert Some(_) = invalid.error
  let #(edited, _) = profile.update(loaded(), profile.NameChanged("New Name"))
  let #(cancelled, _) = profile.update(edited, profile.Cancel)
  cancelled.name |> should.equal("Alex Morgan")
  let #(saving, _) = profile.update(edited, profile.Save)
  saving.pending |> should.be_true
  let #(unchanged, pending) = profile.update(saving, profile.Save)
  pending |> should.equal(effect.none())
  unchanged.name |> should.equal("New Name")
  let markup =
    profile.view(saving, fn(message) { message }) |> element.to_string
  string.contains(markup, "Saving…") |> should.be_true
  string.contains(markup, "disabled") |> should.be_true
}

pub fn failed_save_preserves_draft_and_expiry_hides_personal_data_test() {
  let #(edited, _) = profile.update(loaded(), profile.NameChanged("Draft Name"))
  let #(failed, _) =
    profile.update(edited, profile.Saved(Error(rsvp.NetworkError)))
  failed.name |> should.equal("Draft Name")
  failed.pending |> should.be_false
  let assert Some(_) = failed.error
  let #(expired, _) =
    profile.update(
      failed,
      profile.Saved(
        Error(rsvp.HttpError(response.new(401) |> response.set_body("{}"))),
      ),
    )
  expired.user |> should.equal(None)
  let markup =
    profile.view(expired, fn(message) { message }) |> element.to_string
  string.contains(markup, "Sign in") |> should.be_true
  string.contains(markup, "alex@example.com") |> should.be_false
  string.contains(markup, "Draft Name") |> should.be_false
}

pub fn profile_loading_failure_and_retry_have_clear_states_test() {
  let markup =
    profile.view(profile.init(), fn(message) { message }) |> element.to_string
  string.contains(markup, "Loading your profile") |> should.be_true
  let #(failed, _) =
    profile.update(profile.init(), profile.Loaded(Error(rsvp.NetworkError)))
  let markup =
    profile.view(failed, fn(message) { message }) |> element.to_string
  string.contains(markup, "Try again") |> should.be_true
  let #(retrying, _) = profile.update(failed, profile.Load)
  retrying.loading |> should.be_true
}

pub fn successful_json_save_updates_profile_and_avatar_identity_test() {
  let app =
    simulate.application(
      fn(_) { #(loaded(), effect.none()) },
      profile.update,
      profile.view(_, fn(message) { message }),
    )
    |> simulate.start(Nil)
  let saved =
    app
    |> rsvp.simulate(
      response.new(200)
        |> response.set_header("content-type", "application/json")
        |> response.set_body(
          "{\"id\":\"self\",\"name\":\"New Name\",\"email\":\"alex@example.com\",\"image\":null}",
        ),
      profile.save_handler(),
    )
    |> simulate.model
  saved.name |> should.equal("New Name")
  saved.notice |> should.equal(Some("Your profile has been updated."))
  profile.updated_user(profile.Saved(Ok(user()))) |> should.equal(Some(user()))
  let markup = navigation.avatar(saved.user) |> element.to_string
  string.contains(markup, "New Name") |> should.be_true
}

pub fn profile_route_and_navigation_are_available_to_every_staff_role_test() {
  router.from_href("/staff/profile") |> should.equal(router.Profile)
  router.to_path(router.Profile) |> should.equal("/staff/profile")
  let desktop = navigation.sidebar(router.Profile, False) |> element.to_string
  let mobile = navigation.mobile_nav(router.Profile, False) |> element.to_string
  string.contains(desktop, "/staff/profile") |> should.be_true
  string.contains(mobile, "/staff/profile") |> should.be_true
  string.contains(desktop, "aria-current=\"page\"") |> should.be_true
}

import client/navigation
import client/router
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import shared

pub fn operator_sidebar_contains_only_live_queue_test() {
  let markup =
    navigation.sidebar(router.QueueDashboard, False)
    |> element.to_string
  let assert True = string.contains(markup, "Live queue")
  let assert False = string.contains(markup, "Queue settings")
  let assert False = string.contains(markup, "Organization")
  let assert False = string.contains(markup, "Staff access")
  let assert False = string.contains(markup, "Manage")
  let assert False = string.contains(markup, "Need a hand?")
}

pub fn operator_mobile_navigation_contains_only_live_queue_test() {
  let markup =
    navigation.mobile_nav(router.QueueDashboard, False)
    |> element.to_string
  let assert True = string.contains(markup, "Live queue")
  let assert False = string.contains(markup, "Join")
  let assert False = string.contains(markup, "Settings")
  let assert False = string.contains(markup, "Organization")
}

pub fn administrator_navigation_keeps_management_links_test() {
  let sidebar =
    navigation.sidebar(router.QueueDashboard, True)
    |> element.to_string
  let mobile =
    navigation.mobile_nav(router.QueueDashboard, True)
    |> element.to_string
  let assert True = string.contains(sidebar, "Queue settings")
  let assert True = string.contains(sidebar, "Organization")
  let assert True = string.contains(sidebar, "Staff access")
  let assert True = string.contains(mobile, "Settings")
  let assert True = string.contains(mobile, "Organization")
}

pub fn user_initials_two_words_test() {
  let assert "AM" = navigation.user_initials("Alex Morgan")
  let assert "AM" = navigation.user_initials("   alex   morgan   ")
  Nil
}

pub fn user_initials_single_word_test() {
  let assert "J" = navigation.user_initials("Jane")
  let assert "A" = navigation.user_initials("a")
  Nil
}

pub fn user_initials_multiple_words_test() {
  let assert "AM" = navigation.user_initials("Alex Parker Morgan")
  let assert "MW" = navigation.user_initials("Mary Jane Watson")
  Nil
}

pub fn user_initials_empty_or_whitespace_test() {
  let assert "" = navigation.user_initials("")
  let assert "" = navigation.user_initials("   ")
  Nil
}

pub fn avatar_renders_user_initials_and_accessible_attributes_test() {
  let user =
    shared.User(
      id: "usr_1",
      name: "Alex Morgan",
      email: "alex@example.com",
      image: None,
    )
  let markup = navigation.avatar(Some(user)) |> element.to_string
  let assert True = string.contains(markup, "class=\"avatar\"")
  let assert True = string.contains(markup, "title=\"Alex Morgan\"")
  let assert True =
    string.contains(markup, "aria-label=\"Signed in as Alex Morgan\"")
  let assert True = string.contains(markup, "AM")
  Nil
}

pub fn avatar_falls_back_to_email_initial_when_name_is_blank_test() {
  let user =
    shared.User(
      id: "usr_2",
      name: "   ",
      email: "taylor@example.com",
      image: None,
    )
  let markup = navigation.avatar(Some(user)) |> element.to_string
  let assert True = string.contains(markup, "title=\"taylor@example.com\"")
  let assert True =
    string.contains(markup, "aria-label=\"Signed in as taylor@example.com\"")
  let assert True = string.contains(markup, ">T<")
  Nil
}

pub fn avatar_renders_image_when_provided_test() {
  let user =
    shared.User(
      id: "usr_3",
      name: "Alex Morgan",
      email: "alex@example.com",
      image: Some("https://example.com/avatar.png"),
    )
  let markup = navigation.avatar(Some(user)) |> element.to_string
  let assert True = string.contains(markup, "<img")
  let assert True = string.contains(markup, "class=\"avatar-image\"")
  let assert True =
    string.contains(markup, "src=\"https://example.com/avatar.png\"")
  let assert True = string.contains(markup, "alt=\"Alex Morgan\"")
  let assert True = string.contains(markup, "title=\"Alex Morgan\"")
  Nil
}

pub fn avatar_renders_fallback_when_no_user_present_test() {
  let markup = navigation.avatar(None) |> element.to_string
  let assert True = string.contains(markup, "class=\"avatar\"")
  let assert True = string.contains(markup, "title=\"Signed in\"")
  let assert True = string.contains(markup, "aria-label=\"Signed in\"")
  let assert True = string.contains(markup, "—")
  Nil
}

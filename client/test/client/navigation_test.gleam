import client/navigation
import client/router
import gleam/string
import lustre/element

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

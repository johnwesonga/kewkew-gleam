import gleam/json
import gleam/option.{None}
import server/sql
import server/visitor/queue

pub fn public_location_json_encodes_service_choices_without_database_test() {
  let service =
    sql.ListPublicLocationServices(
      name: "Passport services",
      queue_name: "Passport queue",
      public_id: None,
      availability_state: "open",
      waiting_count: 3,
    )
  let encoded =
    queue.public_location_json("Example organization", "Main location", [
      service,
    ])
    |> json.to_string

  let assert "{\"organization\":\"Example organization\",\"location\":\"Main location\",\"services\":[{\"name\":\"Passport services\",\"queue_name\":\"Passport queue\",\"public_id\":null,\"availability_state\":\"open\",\"waiting_count\":3}]}" =
    encoded
  Nil
}

pub fn public_queue_json_encodes_details_without_database_test() {
  let encoded =
    queue.public_queue_json(sql.GetPublicQueue(
      organization: "Example organization",
      location_id: "location-1",
      location: "Main location",
      service: "Passport services",
      queue: "Passport queue",
      identity_policy: "name_required",
      availability_state: "open",
      available: 1,
      scheduled_service_start_at: None,
    ))
    |> json.to_string

  let assert "{\"organization\":\"Example organization\",\"location_id\":\"location-1\",\"location\":\"Main location\",\"service\":\"Passport services\",\"queue\":\"Passport queue\",\"identity_policy\":\"name_required\",\"availability_state\":\"open\",\"available\":true,\"scheduled_service_start_at\":null}" =
    encoded
  Nil
}

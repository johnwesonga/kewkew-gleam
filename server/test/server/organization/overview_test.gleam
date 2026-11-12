import gleam/dynamic/decode
import gleam/http as gleam_http
import gleam/json
import gleam/result
import gleam/string
import server/authentication
import server/database
import server/http as server_http
import server/organization/bootstrap
import shared.{Admin, Operator}
import shared/json as shared_json
import simplifile
import sqlight
import wisp
import wisp/simulate

pub fn administrator_overview_includes_locations_services_and_queues_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(session) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    add_location(
      connection,
      created.organization_id,
      "location-2",
      "Eastside",
      False,
    )
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "service-1",
      "Food support",
    )
    add_service(
      connection,
      created.organization_id,
      "location-2",
      "service-2",
      "Community advice",
    )
    add_queue(
      connection,
      created.organization_id,
      created.location_id,
      "service-1",
      "queue-1",
      "Food queue",
    )

    let response =
      organization_request(created.organization_id, session.token)
      |> server_http.handle(server_http.Context(database: connection))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert Ok(overview) =
      json.parse(body, using: shared_json.organization_overview_decoder())
    let assert True = overview.organization.name == "Kewkew Test"
    let assert True = overview.role == Admin
    let assert True = overview.can_manage
    let assert [eastside, main] = overview.locations
    let assert True = eastside.location.name == "Eastside"
    let assert False = eastside.location.is_active
    let assert [eastside_service] = eastside.services
    let assert True = eastside_service.queues == []
    let assert True = main.location.name == "Main"
    let assert True = main.location.is_active
    let assert [main_service] = main.services
    let assert [main_queue] = main_service.queues
    let assert True = main_queue.name == "Food queue"
    let assert True = string.contains(body, "Kewkew Test")
    let assert True = string.contains(body, "Main")
    let assert True = string.contains(body, "Eastside")
    let assert True = string.contains(body, "\"is_active\":false")
    let assert True = string.contains(body, "Food support")
    let assert True = string.contains(body, "Community advice")
    let assert True = string.contains(body, "Food queue")
    let assert True = string.contains(body, "\"can_manage\":true")

    let assert Ok(Nil) =
      insert(connection, "INSERT INTO organizations (id, name) VALUES (?, ?)", [
        sqlight.text("other-org"),
        sqlight.text("Private organization"),
      ])
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO organization_memberships (organization_id, user_id, role, status) VALUES (?, ?, 'admin', 'suspended')",
        [
          sqlight.text("other-org"),
          sqlight.text(created.administrator_id),
        ],
      )
    let outside_response =
      organization_request("other-org", session.token)
      |> server_http.handle(server_http.Context(database: connection))
    let assert True = outside_response.status == 404
    let assert wisp.Text(outside_body) = outside_response.body
    let assert False = string.contains(outside_body, "Private organization")
    let list_response =
      simulate.request(gleam_http.Get, "/api/organizations")
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> server_http.handle(server_http.Context(database: connection))
    let assert 200 = list_response.status
    let assert wisp.Text(list_body) = list_response.body
    let assert True = string.contains(list_body, "Kewkew Test")
    let assert False = string.contains(list_body, "Private organization")
    Nil
  })
}

pub fn operator_overview_only_includes_assigned_locations_without_admin_controls_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_location(
      connection,
      created.organization_id,
      "location-2",
      "Eastside",
      True,
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO users (id, name, email, email_verified) VALUES (?, ?, ?, 0)",
        [
          sqlight.text("operator-1"),
          sqlight.text("Test Operator"),
          sqlight.text("operator@example.com"),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO organization_memberships (organization_id, user_id, role, status) VALUES (?, ?, 'operator', 'active')",
        [sqlight.text(created.organization_id), sqlight.text("operator-1")],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO membership_location_access (organization_id, user_id, location_id) VALUES (?, ?, ?)",
        [
          sqlight.text(created.organization_id),
          sqlight.text("operator-1"),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO sessions (id, expires_at, token, created_at, updated_at, user_id) VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+1 day'), ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?)",
        [
          sqlight.text("operator-session"),
          sqlight.text("operator-session-token"),
          sqlight.text("operator-1"),
        ],
      )

    let response =
      organization_request(created.organization_id, "operator-session-token")
      |> server_http.handle(server_http.Context(database: connection))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert Ok(overview) =
      json.parse(body, using: shared_json.organization_overview_decoder())
    let assert True = overview.role == Operator
    let assert False = overview.can_manage
    let assert [assigned_location] = overview.locations
    let assert True = assigned_location.location.name == "Main"
    let assert True = string.contains(body, "Main")
    let assert False = string.contains(body, "Eastside")
    let assert True = string.contains(body, "\"role\":\"operator\"")
    let assert True = string.contains(body, "\"can_manage\":false")
    Nil
  })
}

pub fn organization_overview_requires_a_valid_session_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let response =
      simulate.request(
        gleam_http.Get,
        "/api/organizations/" <> created.organization_id,
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert True = response.status == 401
    Nil
  })
}

pub fn organization_without_locations_returns_an_empty_setup_state_test() {
  with_database(fn(connection) {
    let assert Ok(Nil) =
      insert(connection, "INSERT INTO organizations (id, name) VALUES (?, ?)", [
        sqlight.text("empty-org"),
        sqlight.text("Empty organization"),
      ])
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO users (id, name, email, email_verified) VALUES (?, ?, ?, 0)",
        [
          sqlight.text("empty-admin"),
          sqlight.text("Empty Admin"),
          sqlight.text("empty-admin@example.com"),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO organization_memberships (organization_id, user_id, role, status) VALUES (?, ?, 'admin', 'active')",
        [sqlight.text("empty-org"), sqlight.text("empty-admin")],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO sessions (id, expires_at, token, created_at, updated_at, user_id) VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+1 day'), ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?)",
        [
          sqlight.text("empty-session"),
          sqlight.text("empty-session-token"),
          sqlight.text("empty-admin"),
        ],
      )
    let response =
      organization_request("empty-org", "empty-session-token")
      |> server_http.handle(server_http.Context(database: connection))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert True = string.contains(body, "\"locations\":[]")
    Nil
  })
}

fn organization_request(
  organization_id: String,
  token: String,
) -> wisp.Request {
  simulate.request(gleam_http.Get, "/api/organizations/" <> organization_id)
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
}

fn add_location(
  connection: sqlight.Connection,
  organization_id: String,
  id: String,
  name: String,
  active: Bool,
) -> Nil {
  let assert Ok(Nil) =
    insert(
      connection,
      "INSERT INTO locations (id, organization_id, name, timezone, is_active) VALUES (?, ?, ?, 'UTC', ?)",
      [
        sqlight.text(id),
        sqlight.text(organization_id),
        sqlight.text(name),
        sqlight.bool(active),
      ],
    )
  Nil
}

fn add_service(
  connection: sqlight.Connection,
  organization_id: String,
  location_id: String,
  id: String,
  name: String,
) -> Nil {
  let assert Ok(Nil) =
    insert(
      connection,
      "INSERT INTO services (id, organization_id, location_id, name, description, is_active) VALUES (?, ?, ?, ?, NULL, 1)",
      [
        sqlight.text(id),
        sqlight.text(organization_id),
        sqlight.text(location_id),
        sqlight.text(name),
      ],
    )
  Nil
}

fn add_queue(
  connection: sqlight.Connection,
  organization_id: String,
  location_id: String,
  service_id: String,
  id: String,
  name: String,
) -> Nil {
  let assert Ok(Nil) =
    insert(
      connection,
      "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active) VALUES (?, ?, ?, ?, ?, 'anonymous', 1)",
      [
        sqlight.text(id),
        sqlight.text(organization_id),
        sqlight.text(location_id),
        sqlight.text(service_id),
        sqlight.text(name),
      ],
    )
  Nil
}

fn insert(
  connection: sqlight.Connection,
  sql: String,
  parameters: List(sqlight.Value),
) -> Result(Nil, sqlight.Error) {
  sqlight.query(
    sql <> " RETURNING 'ok'",
    on: connection,
    with: parameters,
    expecting: decode.list(decode.string),
  )
  |> result.map(fn(_) { Nil })
}

fn with_database(run: fn(sqlight.Connection) -> Nil) -> Nil {
  let assert Ok(connection) = sqlight.open(":memory:")
  let assert Ok(schema) = simplifile.read("db/database.sql")
  let assert Ok(Nil) = database.initialize(connection, schema)
  run(connection)
  let _ = sqlight.close(connection)
  Nil
}

fn details() -> bootstrap.Details {
  bootstrap.Details(
    organization_name: "Kewkew Test",
    location_name: "Main",
    admin_name: "Test Admin",
    email: "admin@example.com",
    password: "correct horse battery staple",
    timezone: "UTC",
  )
}

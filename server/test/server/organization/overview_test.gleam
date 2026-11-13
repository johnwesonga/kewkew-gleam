import gleam/dynamic/decode
import gleam/http as gleam_http
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import server/authentication
import server/database
import server/http as server_http
import server/organization/bootstrap
import shared.{Admin, Open, Operator}
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
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('queue-session-1', ?, 'queue-1', 'open', '2026-11-13T08:00:00.000Z')",
        [sqlight.text(created.organization_id)],
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
    let assert True = main_queue.current_session_state == Some(Open)
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
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "main-service",
      "Main service",
    )
    add_service(
      connection,
      created.organization_id,
      "location-2",
      "eastside-service",
      "Eastside service",
    )
    add_queue(
      connection,
      created.organization_id,
      created.location_id,
      "main-service",
      "main-queue",
      "Main queue",
    )
    add_queue(
      connection,
      created.organization_id,
      "location-2",
      "eastside-service",
      "eastside-queue",
      "Eastside queue",
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
    let assert [assigned_service] = assigned_location.services
    let assert [assigned_queue] = assigned_service.queues
    let assert True = assigned_queue.name == "Main queue"
    let assert True = string.contains(body, "Main")
    let assert False = string.contains(body, "Eastside")
    let assert False = string.contains(body, "eastside-queue")
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

pub fn administrator_can_update_organization_name_and_overview_reflects_it_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(session) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let response =
      update_organization_request(
        created.organization_id,
        session.token,
        "  Updated business  ",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert Ok(updated) =
      json.parse(body, using: shared_json.organization_overview_decoder())
    let assert True = updated.organization.name == "Updated business"
    let assert [location] = updated.locations
    let assert True = location.location.name == "Main"
    let assert Ok([["Updated business"]]) =
      sqlight.query(
        "SELECT name FROM organizations WHERE id = ?",
        on: connection,
        with: [sqlight.text(created.organization_id)],
        expecting: decode.list(decode.string),
      )
    Nil
  })
}

pub fn organization_name_update_rejects_blank_names_and_non_admins_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let blank =
      update_organization_request(created.organization_id, admin.token, "   ")
      |> server_http.handle(server_http.Context(database: connection))
    let assert 400 = blank.status
    let operator =
      create_operator_session(
        connection,
        created.organization_id,
        created.location_id,
      )
    let forbidden =
      update_organization_request(
        created.organization_id,
        operator,
        "Operator edit",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 403 = forbidden.status
    let outside =
      update_organization_request("missing-org", admin.token, "Outside edit")
      |> server_http.handle(server_http.Context(database: connection))
    let assert 404 = outside.status
    let assert Ok([["Kewkew Test"]]) =
      sqlight.query(
        "SELECT name FROM organizations WHERE id = ?",
        on: connection,
        with: [sqlight.text(created.organization_id)],
        expecting: decode.list(decode.string),
      )
    Nil
  })
}

pub fn administrator_can_create_and_update_locations_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let create_response =
      location_request(
        gleam_http.Post,
        created.organization_id,
        "",
        admin.token,
        "New Branch",
        "America/Los_Angeles",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 200 = create_response.status
    let assert wisp.Text(created_body) = create_response.body
    let assert Ok(created_overview) =
      json.parse(
        created_body,
        using: shared_json.organization_overview_decoder(),
      )
    let assert [main_location, created_location] = created_overview.locations
    let assert True = created_location.location.name == "New Branch"
    let assert True =
      created_location.location.timezone == "America/Los_Angeles"
    let assert True = main_location.location.id == created.location_id
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "time-service",
      "Timing",
    )
    add_queue(
      connection,
      created.organization_id,
      created.location_id,
      "time-service",
      "time-queue",
      "Timing queue",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('time-session', ?, 'time-queue', 'open', '2025-01-02T03:04:05.000Z')",
        [sqlight.text(created.organization_id)],
      )

    let update_response =
      location_request(
        gleam_http.Put,
        created.organization_id,
        created_location.location.id,
        admin.token,
        "Westside",
        "Pacific/Honolulu",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 200 = update_response.status
    let assert wisp.Text(updated_body) = update_response.body
    let assert Ok(updated_overview) =
      json.parse(
        updated_body,
        using: shared_json.organization_overview_decoder(),
      )
    let assert [unchanged_location, updated_location] =
      updated_overview.locations
    let assert True =
      updated_location.location.id == created_location.location.id
    let assert True = updated_location.location.name == "Westside"
    let assert True = updated_location.location.timezone == "Pacific/Honolulu"
    let assert True = unchanged_location.location.name == "Main"
    let assert Ok([["2025-01-02T03:04:05.000Z"]]) =
      sqlight.query(
        "SELECT opened_at FROM queue_sessions WHERE id = 'time-session'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    Nil
  })
}

pub fn location_routes_validate_timezone_and_require_admin_membership_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let invalid_timezone =
      location_request(
        gleam_http.Post,
        created.organization_id,
        "",
        admin.token,
        "Bad timezone",
        "Mars/Olympus",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 400 = invalid_timezone.status

    let invalid_name =
      location_request(
        gleam_http.Post,
        created.organization_id,
        "",
        admin.token,
        "   ",
        "UTC",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 400 = invalid_name.status

    let operator_token =
      create_operator_session(
        connection,
        created.organization_id,
        created.location_id,
      )
    let operator_create =
      location_request(
        gleam_http.Post,
        created.organization_id,
        "",
        operator_token,
        "Forbidden branch",
        "UTC",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 403 = operator_create.status
    let operator_update =
      location_request(
        gleam_http.Put,
        created.organization_id,
        created.location_id,
        operator_token,
        "Operator edit",
        "UTC",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 403 = operator_update.status

    let unauthenticated =
      simulate.request(
        gleam_http.Post,
        "/api/organizations/" <> created.organization_id <> "/locations",
      )
      |> simulate.string_body("{\"name\":\"No session\",\"timezone\":\"UTC\"}")
      |> server_http.handle(server_http.Context(database: connection))
    let assert 401 = unauthenticated.status
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM locations",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn location_update_cannot_move_a_location_to_another_organization_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO organizations (id, name) VALUES ('other-org', 'Other Org')",
        [],
      )
    add_location(connection, "other-org", "foreign-location", "Foreign", True)
    let response =
      location_request(
        gleam_http.Put,
        created.organization_id,
        "foreign-location",
        admin.token,
        "Moved",
        "UTC",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 404 = response.status
    let assert Ok([["other-org", "Foreign"]]) =
      sqlight.query(
        "SELECT organization_id, name FROM locations WHERE id = 'foreign-location'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    Nil
  })
}

pub fn administrator_can_create_and_update_service_details_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let create_response =
      service_request(
        gleam_http.Post,
        created.organization_id,
        created.location_id,
        "",
        admin.token,
        "  Check-in  ",
        "  Help with arrival  ",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 200 = create_response.status
    let assert wisp.Text(created_body) = create_response.body
    let assert True = string.contains(created_body, "\"name\":\"Check-in\"")
    let assert True =
      string.contains(created_body, "\"description\":\"Help with arrival\"")
    let assert Ok([[service_id, location_id]]) =
      sqlight.query(
        "SELECT id, location_id FROM services WHERE organization_id = ? AND name = 'Check-in'",
        on: connection,
        with: [sqlight.text(created.organization_id)],
        expecting: decode.list(decode.string),
      )
    let update_response =
      service_request(
        gleam_http.Put,
        created.organization_id,
        created.location_id,
        service_id,
        admin.token,
        "Consultation",
        "",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 200 = update_response.status
    let assert wisp.Text(updated_body) = update_response.body
    let assert True = string.contains(updated_body, "\"name\":\"Consultation\"")
    let assert True = string.contains(updated_body, "\"description\":null")
    let assert Ok([[stored_location]]) =
      sqlight.query(
        "SELECT location_id FROM services WHERE id = ?",
        on: connection,
        with: [sqlight.text(service_id)],
        expecting: decode.list(decode.string),
      )
    let assert Ok([[stored_description]]) =
      sqlight.query(
        "SELECT description FROM services WHERE id = ?",
        on: connection,
        with: [sqlight.text(service_id)],
        expecting: decode.list(decode.optional(decode.string)),
      )
    let assert True = location_id == created.location_id
    let assert True = stored_location == created.location_id
    let assert None = stored_description
    Nil
  })
}

pub fn service_management_requires_admin_and_location_scope_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let operator =
      create_operator_session(
        connection,
        created.organization_id,
        created.location_id,
      )
    let denied =
      service_request(
        gleam_http.Post,
        created.organization_id,
        created.location_id,
        "",
        operator,
        "Support",
        "",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 403 = denied.status
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO locations (id, organization_id, name, timezone) VALUES ('other-location', ?, 'Other', 'UTC')",
        [sqlight.text(created.organization_id)],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO services (id, organization_id, location_id, name) VALUES ('service-x', ?, ?, 'Original')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let moved =
      service_request(
        gleam_http.Put,
        created.organization_id,
        "other-location",
        "service-x",
        operator,
        "Moved",
        "",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 403 = moved.status
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let admin_moved =
      service_request(
        gleam_http.Put,
        created.organization_id,
        "other-location",
        "service-x",
        admin.token,
        "Moved",
        "",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 404 = admin_moved.status
    let assert Ok([["Original", original_location]]) =
      sqlight.query(
        "SELECT name, location_id FROM services WHERE id = 'service-x'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    let assert True = original_location == created.location_id
    Nil
  })
}

pub fn service_routes_reject_blank_names_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let response =
      service_request(
        gleam_http.Post,
        created.organization_id,
        created.location_id,
        "",
        admin.token,
        "   ",
        "Description",
      )
      |> server_http.handle(server_http.Context(database: connection))
    let assert 400 = response.status
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM services WHERE organization_id = ?",
        on: connection,
        with: [sqlight.text(created.organization_id)],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

fn service_request(
  method: gleam_http.Method,
  organization_id: String,
  location_id: String,
  service_id: String,
  token: String,
  name: String,
  description: String,
) -> wisp.Request {
  let path =
    "/api/organizations/"
    <> organization_id
    <> "/locations/"
    <> location_id
    <> "/services"
  let path = case method {
    gleam_http.Post -> path
    _ -> path <> "/" <> service_id
  }
  simulate.request(method, path)
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
  |> simulate.string_body(
    "{\"name\":\"" <> name <> "\",\"description\":\"" <> description <> "\"}",
  )
}

fn location_request(
  method: gleam_http.Method,
  organization_id: String,
  location_id: String,
  token: String,
  name: String,
  timezone: String,
) -> wisp.Request {
  let path = "/api/organizations/" <> organization_id <> "/locations"
  let path = case method {
    gleam_http.Post -> path
    _ -> path <> "/" <> location_id
  }
  simulate.request(method, path)
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
  |> simulate.string_body(
    "{\"name\":\"" <> name <> "\",\"timezone\":\"" <> timezone <> "\"}",
  )
}

fn update_organization_request(
  organization_id: String,
  token: String,
  name: String,
) -> wisp.Request {
  simulate.request(gleam_http.Put, "/api/organizations/" <> organization_id)
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
  |> simulate.string_body("{\"name\":\"" <> name <> "\"}")
}

fn create_operator_session(
  connection: sqlight.Connection,
  organization_id: String,
  location_id: String,
) -> String {
  let assert Ok(Nil) =
    insert(
      connection,
      "INSERT INTO users (id, name, email, email_verified) VALUES ('operator-edit', 'Operator', 'operator-edit@example.com', 0)",
      [],
    )
  let assert Ok(Nil) =
    insert(
      connection,
      "INSERT INTO organization_memberships (organization_id, user_id, role, status) VALUES (?, 'operator-edit', 'operator', 'active')",
      [sqlight.text(organization_id)],
    )
  let assert Ok(Nil) =
    insert(
      connection,
      "INSERT INTO membership_location_access (organization_id, user_id, location_id) VALUES (?, 'operator-edit', ?)",
      [sqlight.text(organization_id), sqlight.text(location_id)],
    )
  let assert Ok(Nil) =
    insert(
      connection,
      "INSERT INTO sessions (id, expires_at, token, created_at, updated_at, user_id) VALUES ('operator-edit-session', strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+1 day'), 'operator-edit-token', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), 'operator-edit')",
      [],
    )
  "operator-edit-token"
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

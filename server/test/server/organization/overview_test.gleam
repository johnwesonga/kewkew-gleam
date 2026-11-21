import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/http as gleam_http
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
    let assert True = string.contains(body, created.location_id)
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert True = outside_response.status == 404
    let assert wisp.Text(outside_body) = outside_response.body
    let assert False = string.contains(outside_body, "Private organization")
    let list_response =
      simulate.request(gleam_http.Get, "/api/organizations")
      |> simulate.cookie("kewkew_session", session.token, wisp.PlainText)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = list_response.status
    let assert wisp.Text(list_body) = list_response.body
    let assert True = string.contains(list_body, "Kewkew Test")
    let assert False = string.contains(list_body, "Private organization")
    Nil
  })
}

pub fn public_queue_link_returns_only_visitor_details_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO services (id, organization_id, location_id, name) VALUES ('public-service', ?, ?, 'Food support')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active, public_id) VALUES ('public-queue', ?, ?, 'public-service', 'Main queue', 'anonymous', 1, 'public-secret-id')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('public-session', ?, 'public-queue', 'open', '2026-11-13T08:00:00.000Z')",
        [sqlight.text(created.organization_id)],
      )
    let response =
      simulate.request(gleam_http.Get, "/api/public/queues/public-secret-id")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert True = string.contains(body, "Kewkew Test")
    let assert True = string.contains(body, "Main")
    let assert True = string.contains(body, "Food support")
    let assert True = string.contains(body, "\"available\":true")
    let assert True = string.contains(body, "\"availability_state\":\"open\"")
    let assert False = string.contains(body, "public-queue")

    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queue_sessions SET state = 'paused' WHERE id = 'public-session'",
        [],
      )
    let paused =
      simulate.request(gleam_http.Get, "/api/public/queues/public-secret-id")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert wisp.Text(paused_body) = paused.body
    let assert True =
      string.contains(paused_body, "\"availability_state\":\"paused\"")

    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queue_sessions SET state = 'open' WHERE id = 'public-session'",
        [],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queues SET active_ticket_capacity = 1 WHERE id = 'public-queue'",
        [],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO tickets (id, organization_id, queue_id, queue_session_id, ticket_number, queue_sequence, join_attempt_digest, status, identity_policy, joined_at, created_at, updated_at) VALUES ('public-ticket', ?, 'public-queue', 'public-session', 1, 1, 'public-digest', 'waiting', 'anonymous', '2026-11-14T08:00:00Z', '2026-11-14T08:00:00Z', '2026-11-14T08:00:00Z')",
        [sqlight.text(created.organization_id)],
      )
    let full =
      simulate.request(gleam_http.Get, "/api/public/queues/public-secret-id")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert wisp.Text(full_body) = full.body
    let assert True =
      string.contains(full_body, "\"availability_state\":\"full\"")
    let assert True = string.contains(full_body, "\"available\":false")

    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queues SET is_active = 0 WHERE id = 'public-queue'",
        [],
      )
    let closed =
      simulate.request(gleam_http.Get, "/api/public/queues/public-secret-id")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert wisp.Text(closed_body) = closed.body
    let assert True =
      string.contains(closed_body, "\"availability_state\":\"closed\"")
    let assert True = string.contains(closed_body, "\"available\":false")

    let missing =
      simulate.request(gleam_http.Get, "/api/public/queues/unknown")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 404 = missing.status
    let assert wisp.Text(missing_body) = missing.body
    let assert False = string.contains(missing_body, "Food support")

    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queues SET public_id = NULL WHERE id = 'public-queue'",
        [],
      )
    let revoked =
      simulate.request(gleam_http.Get, "/api/public/queues/public-secret-id")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 404 = revoked.status
    let assert wisp.Text(revoked_body) = revoked.body
    let assert False = string.contains(revoked_body, "Food support")
    let assert False = string.contains(revoked_body, "Kewkew Test")
    Nil
  })
}

pub fn public_location_lists_service_queue_options_and_availability_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO services (id, organization_id, location_id, name) VALUES ('choice-service-open', ?, ?, 'Food support'), ('choice-service-closed', ?, ?, 'Housing help')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active, public_id) VALUES ('choice-queue-open', ?, ?, 'choice-service-open', 'Food line', 'anonymous', 1, 'food-public'), ('choice-queue-open-2', ?, ?, 'choice-service-open', 'Food line 2', 'anonymous', 1, 'food-public-2'), ('choice-queue-closed', ?, ?, 'choice-service-closed', 'Housing line', 'anonymous', 0, 'housing-public')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('choice-session', ?, 'choice-queue-open', 'open', '2026-11-13T08:00:00.000Z')",
        [sqlight.text(created.organization_id)],
      )
    let response =
      simulate.request(
        gleam_http.Get,
        "/api/public/locations/" <> created.location_id,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert True = string.contains(body, "Kewkew Test")
    let assert True = string.contains(body, "Food support")
    let assert True = string.contains(body, "food-public")
    let assert True = string.contains(body, "food-public-2")
    let assert True = string.contains(body, "Food line 2")
    let assert True = string.contains(body, "\"availability_state\":\"open\"")
    let assert True = string.contains(body, "Housing help")
    let assert True = string.contains(body, "housing-public")
    let assert True = string.contains(body, "\"availability_state\":\"closed\"")
    let assert False = string.contains(body, "choice-service-open")
    let assert False = string.contains(body, "choice-queue-open")
    Nil
  })
}

pub fn anonymous_join_creates_private_ticket_and_replays_same_attempt_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "anon-service",
      "Food support",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE services SET description = 'Go to counter 4 and show staff your number.' WHERE id = 'anon-service'",
        [],
      )
    add_queue(
      connection,
      created.organization_id,
      created.location_id,
      "anon-service",
      "anon-queue",
      "Food line",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queues SET public_id = 'anon-public', active_ticket_capacity = 1 WHERE id = 'anon-queue'",
        [],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('anon-session', ?, 'anon-queue', 'open', '2026-11-13T08:00:00.000Z')",
        [sqlight.text(created.organization_id)],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queue_sessions SET scheduled_service_start_at = 'Wednesday, Nov 18, 2026, 11:30 PM · America/Los_Angeles' WHERE id = 'anon-session'",
        [],
      )
    let token = "a7d4b34d-0c2f-4b1b-995e-3ca1e5df7b0b"
    let request = anonymous_join_request("anon-public", token)
    let first =
      request
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 201 = first.status
    let assert wisp.Text(first_body) = first.body
    let assert True = string.contains(first_body, "\"ticket_number\":1")
    let assert True = string.contains(first_body, "\"status\":\"waiting\"")
    let assert True =
      string.contains(first_body, "\"tracking_token\":\"" <> token)
    let second =
      anonymous_join_request("anon-public", token)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 201 = second.status
    let assert wisp.Text(second_body) = second.body
    let assert True = first_body == second_body
    let assert Ok([["[1,2,2]"]]) =
      sqlight.query(
        "SELECT json_array((SELECT count(*) FROM tickets WHERE queue_session_id = 'anon-session'), (SELECT next_ticket_number FROM queue_sessions WHERE id = 'anon-session'), (SELECT next_queue_sequence FROM queue_sessions WHERE id = 'anon-session'))",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    let assert Ok([["[0,1]"]]) =
      sqlight.query(
        "SELECT json_array((SELECT count(*) FROM tracking_credentials WHERE token_digest = ?), (SELECT count(*) FROM tracking_credentials WHERE token_digest = ?))",
        on: connection,
        with: [sqlight.text(token), sqlight.text(token_digest(token))],
        expecting: decode.list(decode.string),
      )
    let tracked =
      simulate.request(gleam_http.Get, "/api/public/tickets/" <> token)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = tracked.status
    let assert wisp.Text(tracked_body) = tracked.body
    let assert True = string.contains(tracked_body, "\"ticket_number\":1")
    let assert True = string.contains(tracked_body, "\"queue_position\":1")
    let assert True =
      string.contains(tracked_body, "\"organization\":\"Kewkew Test\"")
    let assert True =
      string.contains(
        tracked_body,
        "\"scheduled_service_start_at\":\"Wednesday, Nov 18, 2026, 11:30 PM · America/Los_Angeles\"",
      )
    let assert False = string.contains(tracked_body, "tracking_token")
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE tickets SET status = 'called' WHERE join_attempt_digest = ?",
        [sqlight.text(token_digest(token))],
      )
    let called = get_tracking(token, connection)
    let assert 200 = called.status
    let assert wisp.Text(called_body) = called.body
    let assert True = string.contains(called_body, "\"status\":\"called\"")
    let assert True = string.contains(called_body, "\"queue_position\":null")
    let assert True =
      string.contains(
        called_body,
        "\"visitor_instructions\":\"Go to counter 4 and show staff your number.\"",
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE tickets SET status = 'serving' WHERE join_attempt_digest = ?",
        [sqlight.text(token_digest(token))],
      )
    let serving = get_tracking(token, connection)
    let assert wisp.Text(serving_body) = serving.body
    let assert True = string.contains(serving_body, "\"status\":\"serving\"")
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE tickets SET status = 'completed' WHERE join_attempt_digest = ?",
        [sqlight.text(token_digest(token))],
      )
    let completed = get_tracking(token, connection)
    let assert wisp.Text(completed_body) = completed.body
    let assert True =
      string.contains(completed_body, "\"status\":\"completed\"")
    let assert 200 = completed.status
    let assert True = string.contains(completed_body, "\"ticket_number\":1")
    let assert True =
      string.contains(completed_body, "\"service\":\"Food support\"")
    let assert True = string.contains(completed_body, "\"queue_position\":null")
    let assert False = string.contains(completed_body, "token_digest")
    let assert False = string.contains(completed_body, "tracking_token")
    let reopened = get_tracking(token, connection)
    let assert 200 = reopened.status
    let assert wisp.Text(reopened_body) = reopened.body
    let assert True = reopened_body == completed_body
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE tickets SET status = 'no_show' WHERE join_attempt_digest = ?",
        [sqlight.text(token_digest(token))],
      )
    let no_show = get_tracking(token, connection)
    let assert wisp.Text(no_show_body) = no_show.body
    let assert True = string.contains(no_show_body, "\"status\":\"no_show\"")
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE tickets SET status = 'waiting' WHERE join_attempt_digest = ?",
        [sqlight.text(token_digest(token))],
      )
    let malformed =
      simulate.request(gleam_http.Get, "/api/public/tickets/1")
      |> server_http.handle(test_context(connection))
    let assert 404 = malformed.status
    let assert wisp.Text(malformed_body) = malformed.body
    let assert False = string.contains(malformed_body, "Food line")
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT count(*) FROM tracking_credentials WHERE token_digest = ? AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now') AND expires_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+25 hours')",
        on: connection,
        with: [sqlight.text(token_digest(token))],
        expecting: decode.list(decode.int),
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE tracking_credentials SET revoked_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE token_digest = ?",
        [sqlight.text(token_digest(token))],
      )
    let revoked =
      simulate.request(gleam_http.Get, "/api/public/tickets/" <> token)
      |> server_http.handle(test_context(connection))
    let assert 404 = revoked.status
    let assert wisp.Text(revoked_body) = revoked.body
    let assert False = string.contains(revoked_body, "Food line")
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE tracking_credentials SET revoked_at = NULL, expires_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 second') WHERE token_digest = ?",
        [sqlight.text(token_digest(token))],
      )
    let expired =
      simulate.request(gleam_http.Get, "/api/public/tickets/" <> token)
      |> server_http.handle(test_context(connection))
    let assert 404 = expired.status
    let assert wisp.Text(expired_body) = expired.body
    let assert False = string.contains(expired_body, "Food line")
    let number_only =
      simulate.request(gleam_http.Get, "/api/public/tickets/1")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 404 = number_only.status
    let full =
      anonymous_join_request(
        "anon-public",
        "13a4f0ca-5163-4e37-9279-81c4ebc71636",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 409 = full.status
    let assert wisp.Text(full_body) = full.body
    let assert True = string.contains(full_body, "queue is full")
    Nil
  })
}

pub fn anonymous_join_rejects_closed_and_name_required_queues_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "join-service",
      "Community help",
    )
    add_queue(
      connection,
      created.organization_id,
      created.location_id,
      "join-service",
      "closed-queue",
      "Closed line",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queues SET public_id = 'closed-public' WHERE id = 'closed-queue'",
        [],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active, public_id) VALUES ('named-queue', ?, ?, 'join-service', 'Named line', 'name_required', 1, 'named-public')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('named-session', ?, 'named-queue', 'open', '2026-11-13T08:00:00.000Z')",
        [sqlight.text(created.organization_id)],
      )
    let closed =
      anonymous_join_request(
        "closed-public",
        "f235c8b4-d88f-4bbf-9b69-57bc0960eb82",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 409 = closed.status
    let assert wisp.Text(closed_body) = closed.body
    let assert True = string.contains(closed_body, "not accepting visitors")
    let named =
      anonymous_join_request(
        "named-public",
        "0684c3b6-d313-45a1-a32e-f33697307784",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 400 = named.status
    let assert wisp.Text(named_body) = named.body
    let assert True = string.contains(named_body, "first name is required")
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT count(*) FROM tickets",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn name_required_join_validates_both_names_and_persists_them_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "name-service",
      "Support",
    )
    add_queue(
      connection,
      created.organization_id,
      created.location_id,
      "name-service",
      "name-queue",
      "Main line",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queues SET identity_policy = 'name_required', public_id = 'name-public' WHERE id = 'name-queue'",
        [],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('name-session', ?, 'name-queue', 'open', '2026-11-13T08:00:00.000Z')",
        [sqlight.text(created.organization_id)],
      )
    let missing_first =
      visitor_join_request(
        "name-public",
        "d1081bf8-0023-4c5b-8c41-fad2f389eabb",
        None,
        Some("Smith"),
      )
      |> server_http.handle(test_context(connection))
    let assert 400 = missing_first.status
    let assert wisp.Text(first_error) = missing_first.body
    let assert True = string.contains(first_error, "first name is required")
    let missing_last =
      visitor_join_request(
        "name-public",
        "0e83b27a-3ec0-4913-a91f-700229621739",
        Some("Alex"),
        None,
      )
      |> server_http.handle(test_context(connection))
    let assert 400 = missing_last.status
    let assert wisp.Text(last_error) = missing_last.body
    let assert True = string.contains(last_error, "last name is required")
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT count(*) FROM tickets",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    let success =
      visitor_join_request(
        "name-public",
        "2c6646ce-d155-4bc4-87a1-9f4dbff26aae",
        Some("  Alex "),
        Some(" Smith "),
      )
      |> server_http.handle(test_context(connection))
    let assert 201 = success.status
    let tracked =
      simulate.request(
        gleam_http.Get,
        "/api/public/tickets/2c6646ce-d155-4bc4-87a1-9f4dbff26aae",
      )
      |> server_http.handle(test_context(connection))
    let assert 200 = tracked.status
    let assert wisp.Text(tracked_body) = tracked.body
    let assert True =
      string.contains(tracked_body, "\"visitor_first_name\":\"Alex\"")
    let assert False = string.contains(tracked_body, "Smith")
    let assert Ok([["[\"name_required\",\"Alex\",\"Smith\"]"]]) =
      sqlight.query(
        "SELECT json_array(identity_policy, first_name, last_name) FROM tickets",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    Nil
  })
}

pub fn visitor_can_cancel_waiting_ticket_once_but_not_after_call_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "cancel-service",
      "Support",
    )
    add_queue(
      connection,
      created.organization_id,
      created.location_id,
      "cancel-service",
      "cancel-queue",
      "Main line",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queues SET public_id = 'cancel-public' WHERE id = 'cancel-queue'",
        [],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('cancel-session', ?, 'cancel-queue', 'open', '2026-11-13T08:00:00.000Z')",
        [sqlight.text(created.organization_id)],
      )
    let first_token = "954bba30-d871-4156-8b62-fef9a7fba111"
    let second_token = "ce5bf8f1-b28d-489d-b432-554fd69df222"
    let first_join =
      anonymous_join_request("cancel-public", first_token)
      |> server_http.handle(test_context(connection))
    let assert 201 = first_join.status
    let second_join =
      anonymous_join_request("cancel-public", second_token)
      |> server_http.handle(test_context(connection))
    let assert 201 = second_join.status
    let before_cancel = get_tracking(second_token, connection)
    let assert wisp.Text(before_body) = before_cancel.body
    let assert True = string.contains(before_body, "\"queue_position\":2")
    let cancelled = cancel_tracking(first_token, connection)
    let assert 200 = cancelled.status
    let assert wisp.Text(cancelled_body) = cancelled.body
    let assert True =
      string.contains(cancelled_body, "\"status\":\"cancelled\"")
    let assert True = string.contains(cancelled_body, "\"queue_position\":null")
    let after_cancel = get_tracking(second_token, connection)
    let assert wisp.Text(after_body) = after_cancel.body
    let assert True = string.contains(after_body, "\"queue_position\":1")
    let repeated = cancel_tracking(first_token, connection)
    let assert 200 = repeated.status
    let assert wisp.Text(repeated_body) = repeated.body
    let assert True = string.contains(repeated_body, "\"status\":\"cancelled\"")
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT count(*) FROM ticket_events WHERE ticket_id = (SELECT ticket_id FROM tracking_credentials WHERE token_digest = ?) AND actor_type = 'visitor' AND from_status = 'waiting' AND to_status = 'cancelled'",
        on: connection,
        with: [sqlight.text(token_digest(first_token))],
        expecting: decode.list(decode.int),
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE tickets SET status = 'called', called_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE join_attempt_digest = ?",
        [sqlight.text(token_digest(second_token))],
      )
    let refused = cancel_tracking(second_token, connection)
    let assert 409 = refused.status
    let assert wisp.Text(refused_body) = refused.body
    let assert True =
      string.contains(refused_body, "only be cancelled while waiting")
    let assert Ok([["called"]]) =
      sqlight.query(
        "SELECT status FROM tickets WHERE join_attempt_digest = ?",
        on: connection,
        with: [sqlight.text(token_digest(second_token))],
        expecting: decode.list(decode.string),
      )
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
          sqlight.text(token_digest("operator-session-token")),
          sqlight.text("operator-1"),
        ],
      )

    let response =
      organization_request(created.organization_id, "operator-session-token")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 403 = forbidden.status
    let outside =
      update_organization_request("missing-org", admin.token, "Outside edit")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 403 = operator_update.status

    let unauthenticated =
      simulate.request(
        gleam_http.Post,
        "/api/organizations/" <> created.organization_id <> "/locations",
      )
      |> simulate.string_body("{\"name\":\"No session\",\"timezone\":\"UTC\"}")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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

pub fn administrator_can_deactivate_and_reactivate_service_preserving_queues_test() {
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
        "INSERT INTO services (id, organization_id, location_id, name) VALUES ('service-availability', ?, ?, 'Support')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, active_ticket_capacity) VALUES ('queue-availability', ?, ?, 'service-availability', 'Main', 'anonymous', 10)",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let request =
      availability_request(
        created.organization_id,
        created.location_id,
        "service-availability",
        admin.token,
        False,
      )
    let response =
      request
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert True = string.contains(body, "\"is_active\":false")
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT is_active FROM services WHERE id = 'service-availability'",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM queues WHERE id = 'queue-availability'",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    let response =
      availability_request(
        created.organization_id,
        created.location_id,
        "service-availability",
        admin.token,
        True,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert True = string.contains(body, "\"is_active\":true")
    Nil
  })
}

pub fn administrator_can_deactivate_location_without_deleting_queue_history_test() {
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
        "INSERT INTO services (id, organization_id, location_id, name) VALUES ('location-service', ?, ?, 'Support')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active) VALUES ('location-queue', ?, ?, 'location-service', 'Main', 'anonymous', 1)",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state) VALUES ('location-session', ?, 'location-queue', 'open')",
        [sqlight.text(created.organization_id)],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO tickets (id, organization_id, queue_id, queue_session_id, ticket_number, queue_sequence, join_attempt_digest, status, identity_policy, joined_at, created_at, updated_at) VALUES ('location-ticket', ?, 'location-queue', 'location-session', 1, 1, 'ticket-digest', 'waiting', 'anonymous', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [sqlight.text(created.organization_id)],
      )
    let response =
      location_availability_request(
        created.organization_id,
        created.location_id,
        admin.token,
        False,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert True = string.contains(body, "\"is_active\":false")
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT is_active FROM locations WHERE id = ?",
        on: connection,
        with: [sqlight.text(created.location_id)],
        expecting: decode.list(decode.int),
      )
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM services WHERE location_id = ?",
        on: connection,
        with: [sqlight.text(created.location_id)],
        expecting: decode.list(decode.int),
      )
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM queues WHERE location_id = ?",
        on: connection,
        with: [sqlight.text(created.location_id)],
        expecting: decode.list(decode.int),
      )
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM queue_sessions WHERE id = 'location-session'",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM tickets WHERE id = 'location-ticket'",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    let response =
      location_availability_request(
        created.organization_id,
        created.location_id,
        admin.token,
        True,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert True = string.contains(body, "\"is_active\":true")
    Nil
  })
}

pub fn location_availability_change_requires_an_organization_admin_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let operator =
      create_operator_session(
        connection,
        created.organization_id,
        created.location_id,
      )
    let response =
      location_availability_request(
        created.organization_id,
        created.location_id,
        operator,
        False,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 403 = response.status
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT is_active FROM locations WHERE id = ?",
        on: connection,
        with: [sqlight.text(created.location_id)],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

fn location_availability_request(
  organization_id: String,
  location_id: String,
  token: String,
  is_active: Bool,
) -> wisp.Request {
  simulate.request(
    gleam_http.Patch,
    "/api/organizations/" <> organization_id <> "/locations/" <> location_id,
  )
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
  |> simulate.string_body(json.to_string(json.bool(is_active)))
}

pub fn service_availability_changes_require_admin_and_correct_location_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    let operator =
      create_operator_session(
        connection,
        created.organization_id,
        created.location_id,
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO services (id, organization_id, location_id, name) VALUES ('service-availability', ?, ?, 'Support')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let denied =
      availability_request(
        created.organization_id,
        created.location_id,
        "service-availability",
        operator,
        False,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 403 = denied.status
    let wrong_location =
      availability_request(
        created.organization_id,
        "other-location",
        "service-availability",
        operator,
        False,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 403 = wrong_location.status
    Nil
  })
}

fn availability_request(
  organization_id: String,
  location_id: String,
  service_id: String,
  token: String,
  is_active: Bool,
) -> wisp.Request {
  simulate.request(
    gleam_http.Patch,
    "/api/organizations/"
      <> organization_id
      <> "/locations/"
      <> location_id
      <> "/services/"
      <> service_id,
  )
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
  |> simulate.string_body(json.to_string(json.bool(is_active)))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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

pub fn administrator_can_create_a_queue_without_opening_a_session_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "queue-service",
      "Consultation",
    )
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let response =
      queue_request(
        created.organization_id,
        created.location_id,
        "queue-service",
        admin.token,
        "  Morning line  ",
        "name_required",
        "4",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = response.status
    let assert wisp.Text(body) = response.body
    let assert Ok(overview) =
      json.parse(body, using: shared_json.organization_overview_decoder())
    let assert [location] = overview.locations
    let assert [service] = location.services
    let assert [queue] = service.queues
    let assert True = queue.name == "Morning line"
    let assert True = queue.identity_policy == shared.NameRequired
    let assert True = queue.active_ticket_capacity == Some(4)
    let assert False = queue.is_active
    let assert True = queue.current_session_state == None
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM queue_sessions WHERE queue_id = ?",
        on: connection,
        with: [sqlight.text(queue.id)],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn administrator_can_edit_queue_configuration_without_changing_session_or_tickets_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "queue-service",
      "Consultation",
    )
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let created_queue =
      queue_request(
        created.organization_id,
        created.location_id,
        "queue-service",
        admin.token,
        "Morning line",
        "anonymous",
        "4",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert wisp.Text(create_body) = created_queue.body
    let assert Ok(overview) =
      json.parse(
        create_body,
        using: shared_json.organization_overview_decoder(),
      )
    let assert [location] = overview.locations
    let assert [service] = location.services
    let assert [queue] = service.queues
    let assert Some(public_id) = queue.public_id
    let assert Ok(Nil) =
      insert(connection, "UPDATE queues SET is_active = 1 WHERE id = ?", [
        sqlight.text(queue.id),
      ])

    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('edit-session', ?, ?, 'open', '2026-11-14T08:00:00Z')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(queue.id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO tickets (id, organization_id, queue_id, queue_session_id, ticket_number, queue_sequence, join_attempt_digest, status, identity_policy, joined_at, created_at, updated_at) VALUES ('edit-ticket', ?, ?, 'edit-session', 1, 1, 'edit-digest', 'waiting', 'anonymous', '2026-11-14T08:05:00Z', '2026-11-14T08:05:00Z', '2026-11-14T08:05:00Z')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(queue.id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO tickets (id, organization_id, queue_id, queue_session_id, ticket_number, queue_sequence, join_attempt_digest, status, identity_policy, joined_at, created_at, updated_at) VALUES ('edit-ticket-2', ?, ?, 'edit-session', 2, 2, 'edit-digest-2', 'serving', 'anonymous', '2026-11-14T08:06:00Z', '2026-11-14T08:06:00Z', '2026-11-14T08:06:00Z')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(queue.id),
        ],
      )

    let updated =
      queue_update_request(
        gleam_http.Put,
        created.organization_id,
        created.location_id,
        "queue-service",
        queue.id,
        admin.token,
        "Afternoon line",
        "name_required",
        "1",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = updated.status
    let assert wisp.Text(updated_body) = updated.body
    let assert Ok(updated_overview) =
      json.parse(
        updated_body,
        using: shared_json.organization_overview_decoder(),
      )
    let assert [updated_location] = updated_overview.locations
    let assert [updated_service] = updated_location.services
    let assert [updated_queue] = updated_service.queues
    let assert True = updated_queue.id == queue.id
    let assert True = updated_queue.name == "Afternoon line"
    let assert True = updated_queue.identity_policy == shared.NameRequired
    let assert True = updated_queue.active_ticket_capacity == Some(1)
    let assert True = updated_queue.public_id == Some(public_id)

    let assert Ok([["[\"open\",\"2026-11-14T08:00:00Z\",1]"]]) =
      sqlight.query(
        "SELECT json_array(state, opened_at, next_ticket_number) FROM queue_sessions WHERE id = 'edit-session'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    let assert Ok([["[1,1,\"waiting\",\"anonymous\"]"]]) =
      sqlight.query(
        "SELECT json_array(ticket_number, queue_sequence, status, identity_policy) FROM tickets WHERE id = 'edit-ticket'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    let assert Ok([[2]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM tickets WHERE queue_session_id = 'edit-session' AND status IN ('waiting', 'called', 'serving')",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    let full =
      simulate.request(gleam_http.Get, "/api/public/queues/" <> public_id)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert wisp.Text(full_body) = full.body
    let assert True =
      string.contains(full_body, "\"availability_state\":\"full\"")

    let unlimited =
      queue_update_request(
        gleam_http.Put,
        created.organization_id,
        created.location_id,
        "queue-service",
        queue.id,
        admin.token,
        "Afternoon line",
        "name_required",
        "null",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = unlimited.status
    let assert wisp.Text(unlimited_body) = unlimited.body
    let assert True =
      string.contains(unlimited_body, "\"active_ticket_capacity\":null")
    let available =
      simulate.request(gleam_http.Get, "/api/public/queues/" <> public_id)
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert wisp.Text(available_body) = available.body
    let assert True =
      string.contains(available_body, "\"availability_state\":\"open\"")

    let operator =
      create_operator_session(
        connection,
        created.organization_id,
        created.location_id,
      )
    let denied =
      queue_update_request(
        gleam_http.Put,
        created.organization_id,
        created.location_id,
        "queue-service",
        queue.id,
        operator,
        "Operator edit",
        "anonymous",
        "null",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 403 = denied.status

    let invalid_capacity =
      queue_update_request(
        gleam_http.Put,
        created.organization_id,
        created.location_id,
        "queue-service",
        queue.id,
        admin.token,
        "Afternoon line",
        "name_required",
        "0",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 400 = invalid_capacity.status
    Nil
  })
}

pub fn administrator_can_deactivate_and_reactivate_queue_without_changing_history_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "availability-service",
      "Consultation",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active, public_id) VALUES ('availability-queue', ?, ?, 'availability-service', 'Consultation line', 'anonymous', 1, 'availability-public-id')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queue_sessions (id, organization_id, queue_id, state, opened_at) VALUES ('availability-session', ?, 'availability-queue', 'open', '2026-11-18T08:00:00Z')",
        [sqlight.text(created.organization_id)],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO tickets (id, organization_id, queue_id, queue_session_id, ticket_number, queue_sequence, join_attempt_digest, status, identity_policy, joined_at, created_at, updated_at) VALUES ('availability-ticket', ?, 'availability-queue', 'availability-session', 1, 1, 'availability-join-digest', 'serving', 'anonymous', '2026-11-18T08:05:00Z', '2026-11-18T08:05:00Z', '2026-11-18T08:05:00Z')",
        [sqlight.text(created.organization_id)],
      )
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )

    let deactivated =
      queue_availability_request(
        created.organization_id,
        created.location_id,
        "availability-service",
        "availability-queue",
        admin.token,
        False,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = deactivated.status
    let assert wisp.Text(deactivated_body) = deactivated.body
    let assert Ok(deactivated_overview) =
      json.parse(
        deactivated_body,
        using: shared_json.organization_overview_decoder(),
      )
    let assert [location] = deactivated_overview.locations
    let assert [service] = location.services
    let assert [queue] = service.queues
    let assert False = queue.is_active

    let unavailable =
      simulate.request(
        gleam_http.Get,
        "/api/public/queues/availability-public-id",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert wisp.Text(unavailable_body) = unavailable.body
    let assert True =
      string.contains(unavailable_body, "\"availability_state\":\"closed\"")
    let assert True = string.contains(unavailable_body, "\"available\":false")
    let assert Ok([["[\"open\",\"serving\"]"]]) =
      sqlight.query(
        "SELECT json_array(queue_sessions.state, tickets.status) FROM queue_sessions JOIN tickets ON tickets.queue_session_id = queue_sessions.id WHERE queue_sessions.id = 'availability-session' AND tickets.id = 'availability-ticket'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )

    let reactivated =
      queue_availability_request(
        created.organization_id,
        created.location_id,
        "availability-service",
        "availability-queue",
        admin.token,
        True,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 200 = reactivated.status
    let available =
      simulate.request(
        gleam_http.Get,
        "/api/public/queues/availability-public-id",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert wisp.Text(available_body) = available.body
    let assert True =
      string.contains(available_body, "\"availability_state\":\"open\"")
    let assert True = string.contains(available_body, "\"available\":true")
    Nil
  })
}

pub fn queue_availability_change_requires_admin_and_exact_queue_scope_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "availability-service",
      "Consultation",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active, public_id) VALUES ('availability-queue', ?, ?, 'availability-service', 'Consultation line', 'anonymous', 1, 'availability-public-id')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let operator_token =
      create_operator_session(
        connection,
        created.organization_id,
        created.location_id,
      )
    let denied =
      queue_availability_request(
        created.organization_id,
        created.location_id,
        "availability-service",
        "availability-queue",
        operator_token,
        False,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 403 = denied.status

    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let stale =
      queue_availability_request(
        created.organization_id,
        created.location_id,
        "wrong-service",
        "availability-queue",
        admin.token,
        False,
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 404 = stale.status
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT is_active FROM queues WHERE id = 'availability-queue'",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn admin_opens_session_only_when_queue_location_and_service_are_active_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "open-service",
      "Consultation",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active, public_id) VALUES ('open-queue', ?, ?, 'open-service', 'Consultation line', 'anonymous', 0, 'open-public-id')",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let ctx =
      server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      )

    let inactive_queue =
      open_queue_session_request(
        created.organization_id,
        created.location_id,
        "open-service",
        "open-queue",
        admin.token,
      )
      |> server_http.handle(ctx)
    let assert 409 = inactive_queue.status
    let assert wisp.Text(inactive_queue_body) = inactive_queue.body
    let assert True =
      string.contains(inactive_queue_body, "activate this queue")

    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE queues SET is_active = 1 WHERE id = 'open-queue'",
        [],
      )
    let assert Ok(Nil) =
      insert(connection, "UPDATE locations SET is_active = 0 WHERE id = ?", [
        sqlight.text(created.location_id),
      ])
    let inactive_location =
      open_queue_session_request(
        created.organization_id,
        created.location_id,
        "open-service",
        "open-queue",
        admin.token,
      )
      |> server_http.handle(ctx)
    let assert 409 = inactive_location.status
    let assert wisp.Text(inactive_location_body) = inactive_location.body
    let assert True =
      string.contains(inactive_location_body, "activate this location")

    let assert Ok(Nil) =
      insert(connection, "UPDATE locations SET is_active = 1 WHERE id = ?", [
        sqlight.text(created.location_id),
      ])
    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE services SET is_active = 0 WHERE id = 'open-service'",
        [],
      )
    let inactive_service =
      open_queue_session_request(
        created.organization_id,
        created.location_id,
        "open-service",
        "open-queue",
        admin.token,
      )
      |> server_http.handle(ctx)
    let assert 409 = inactive_service.status
    let assert wisp.Text(inactive_service_body) = inactive_service.body
    let assert True =
      string.contains(inactive_service_body, "activate this service")

    let assert Ok(Nil) =
      insert(
        connection,
        "UPDATE services SET is_active = 1 WHERE id = 'open-service'",
        [],
      )
    let opened =
      open_queue_session_request(
        created.organization_id,
        created.location_id,
        "open-service",
        "open-queue",
        admin.token,
      )
      |> server_http.handle(ctx)
    let assert 200 = opened.status
    let assert wisp.Text(opened_body) = opened.body
    let assert Ok(overview) =
      json.parse(
        opened_body,
        using: shared_json.organization_overview_decoder(),
      )
    let assert [location] = overview.locations
    let assert [service] = location.services
    let assert [queue] = service.queues
    let assert True = queue.current_session_state == Some(Open)
    let assert True = queue.is_active
    let assert Ok([["[\"open\",1,1]"]]) =
      sqlight.query(
        "SELECT json_array(state, next_ticket_number, next_queue_sequence) FROM queue_sessions WHERE queue_id = 'open-queue'",
        on: connection,
        with: [],
        expecting: decode.list(decode.string),
      )
    let public_page =
      simulate.request(gleam_http.Get, "/api/public/queues/open-public-id")
      |> server_http.handle(ctx)
    let assert wisp.Text(public_body) = public_page.body
    let assert True =
      string.contains(public_body, "\"availability_state\":\"open\"")

    let repeated =
      open_queue_session_request(
        created.organization_id,
        created.location_id,
        "open-service",
        "open-queue",
        admin.token,
      )
      |> server_http.handle(ctx)
    let assert 409 = repeated.status
    let assert Ok([[1]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM queue_sessions WHERE queue_id = 'open-queue' AND state IN ('open', 'paused')",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn assigned_operator_can_open_queue_but_unassigned_operator_cannot_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "assigned-service",
      "Main service",
    )
    add_location(
      connection,
      created.organization_id,
      "other-location",
      "Other",
      True,
    )
    add_service(
      connection,
      created.organization_id,
      "other-location",
      "other-service",
      "Other service",
    )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active) VALUES ('assigned-queue', ?, ?, 'assigned-service', 'Assigned', 'anonymous', 1)",
        [
          sqlight.text(created.organization_id),
          sqlight.text(created.location_id),
        ],
      )
    let assert Ok(Nil) =
      insert(
        connection,
        "INSERT INTO queues (id, organization_id, location_id, service_id, name, identity_policy, is_active) VALUES ('unassigned-queue', ?, 'other-location', 'other-service', 'Unassigned', 'anonymous', 1)",
        [sqlight.text(created.organization_id)],
      )
    let operator_token =
      create_operator_session(
        connection,
        created.organization_id,
        created.location_id,
      )
    let ctx =
      server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      )
    let opened =
      open_queue_session_request(
        created.organization_id,
        created.location_id,
        "assigned-service",
        "assigned-queue",
        operator_token,
      )
      |> server_http.handle(ctx)
    let assert 200 = opened.status
    let denied =
      open_queue_session_request(
        created.organization_id,
        "other-location",
        "other-service",
        "unassigned-queue",
        operator_token,
      )
      |> server_http.handle(ctx)
    let assert 403 = denied.status
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM queue_sessions WHERE queue_id = 'unassigned-queue'",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn queue_creation_rejects_invalid_fields_and_mismatched_service_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "queue-service",
      "Consultation",
    )
    add_location(
      connection,
      created.organization_id,
      "other-location",
      "Other",
      True,
    )
    let assert Ok(admin) =
      authentication.sign_in(
        connection,
        "admin@example.com",
        "correct horse battery staple",
      )
    let blank_name =
      queue_request(
        created.organization_id,
        created.location_id,
        "queue-service",
        admin.token,
        "   ",
        "anonymous",
        "null",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 400 = blank_name.status
    let invalid_capacity =
      queue_request(
        created.organization_id,
        created.location_id,
        "queue-service",
        admin.token,
        "Morning line",
        "anonymous",
        "0",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 400 = invalid_capacity.status
    let invalid_policy =
      queue_request(
        created.organization_id,
        created.location_id,
        "queue-service",
        admin.token,
        "Morning line",
        "email_required",
        "null",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 400 = invalid_policy.status
    let mismatched_pair =
      queue_request(
        created.organization_id,
        "other-location",
        "queue-service",
        admin.token,
        "Morning line",
        "anonymous",
        "null",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 404 = mismatched_pair.status
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM queues",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

pub fn only_an_administrator_can_create_queues_test() {
  with_database(fn(connection) {
    let assert Ok(created) = bootstrap.create(connection, details())
    add_service(
      connection,
      created.organization_id,
      created.location_id,
      "queue-service",
      "Consultation",
    )
    let operator =
      create_operator_session(
        connection,
        created.organization_id,
        created.location_id,
      )
    let denied =
      queue_request(
        created.organization_id,
        created.location_id,
        "queue-service",
        operator,
        "Morning line",
        "anonymous",
        "null",
      )
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
    let assert 403 = denied.status
    let assert Ok([[0]]) =
      sqlight.query(
        "SELECT COUNT(*) FROM queues",
        on: connection,
        with: [],
        expecting: decode.list(decode.int),
      )
    Nil
  })
}

fn queue_request(
  organization_id: String,
  location_id: String,
  service_id: String,
  token: String,
  name: String,
  identity_policy: String,
  capacity_json: String,
) -> wisp.Request {
  simulate.request(
    gleam_http.Post,
    "/api/organizations/"
      <> organization_id
      <> "/locations/"
      <> location_id
      <> "/services/"
      <> service_id
      <> "/queues",
  )
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
  |> simulate.string_body(
    "{\"name\":\""
    <> name
    <> "\",\"identity_policy\":\""
    <> identity_policy
    <> "\",\"active_ticket_capacity\":"
    <> capacity_json
    <> "}",
  )
}

fn queue_update_request(
  method: gleam_http.Method,
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
  token: String,
  name: String,
  identity_policy: String,
  capacity_json: String,
) -> wisp.Request {
  simulate.request(
    method,
    "/api/organizations/"
      <> organization_id
      <> "/locations/"
      <> location_id
      <> "/services/"
      <> service_id
      <> "/queues/"
      <> queue_id,
  )
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
  |> simulate.string_body(
    "{\"name\":\""
    <> name
    <> "\",\"identity_policy\":\""
    <> identity_policy
    <> "\",\"active_ticket_capacity\":"
    <> capacity_json
    <> "}",
  )
}

fn queue_availability_request(
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
  token: String,
  is_active: Bool,
) -> wisp.Request {
  simulate.request(
    gleam_http.Patch,
    "/api/organizations/"
      <> organization_id
      <> "/locations/"
      <> location_id
      <> "/services/"
      <> service_id
      <> "/queues/"
      <> queue_id,
  )
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
  |> simulate.string_body(json.to_string(json.bool(is_active)))
}

fn open_queue_session_request(
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
  token: String,
) -> wisp.Request {
  simulate.request(
    gleam_http.Post,
    "/api/organizations/"
      <> organization_id
      <> "/locations/"
      <> location_id
      <> "/services/"
      <> service_id
      <> "/queues/"
      <> queue_id
      <> "/sessions",
  )
  |> simulate.cookie("kewkew_session", token, wisp.PlainText)
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
      "INSERT INTO sessions (id, expires_at, token, created_at, updated_at, user_id) VALUES ('operator-edit-session', strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+1 day'), ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), 'operator-edit')",
      [sqlight.text(token_digest("operator-edit-token"))],
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
          sqlight.text(token_digest("empty-session-token")),
          sqlight.text("empty-admin"),
        ],
      )
    let response =
      organization_request("empty-org", "empty-session-token")
      |> server_http.handle(server_http.Context(
        database: connection,
        resend_api_key: "",
        resend_from: "",
        public_app_url: "http://localhost:8080",
      ))
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

fn anonymous_join_request(public_id: String, token: String) -> wisp.Request {
  visitor_join_request(public_id, token, None, None)
}

fn visitor_join_request(
  public_id: String,
  token: String,
  first_name: Option(String),
  last_name: Option(String),
) -> wisp.Request {
  let fields = [#("join_attempt_token", json.string(token))]
  let fields = case first_name {
    Some(value) -> list.append(fields, [#("first_name", json.string(value))])
    None -> fields
  }
  let fields = case last_name {
    Some(value) -> list.append(fields, [#("last_name", json.string(value))])
    None -> fields
  }
  simulate.request(
    gleam_http.Post,
    "/api/public/queues/" <> public_id <> "/tickets",
  )
  |> simulate.string_body(json.to_string(json.object(fields)))
}

fn test_context(connection: sqlight.Connection) -> server_http.Context {
  server_http.Context(
    database: connection,
    resend_api_key: "",
    resend_from: "",
    public_app_url: "http://localhost:8080",
  )
}

fn get_tracking(
  token: String,
  connection: sqlight.Connection,
) -> wisp.Response {
  simulate.request(gleam_http.Get, "/api/public/tickets/" <> token)
  |> server_http.handle(test_context(connection))
}

fn cancel_tracking(
  token: String,
  connection: sqlight.Connection,
) -> wisp.Response {
  simulate.request(gleam_http.Delete, "/api/public/tickets/" <> token)
  |> server_http.handle(test_context(connection))
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

fn token_digest(token: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(token))
  |> bit_array.base16_encode
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

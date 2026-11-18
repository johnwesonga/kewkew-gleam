import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import server/id
import sqlight

pub type TicketError {
  InvalidJoinAttempt
  QueueUnavailable
  QueueRequiresName
  QueueFull
  DatabaseFailure(String)
}

type JoinTarget {
  JoinTarget(
    queue_id: String,
    identity_policy: String,
    session_id: String,
    ticket_number: Int,
    queue_sequence: Int,
    queue_capacity: Option(Int),
    occurrence_capacity: Option(Int),
    active_count: Int,
  )
}

pub fn join_anonymous(
  connection: sqlight.Connection,
  public_id: String,
  join_attempt_token: String,
) -> Result(String, TicketError) {
  case valid_token(join_attempt_token) {
    False -> Error(InvalidJoinAttempt)
    True -> {
      let digest = token_digest(join_attempt_token)
      case sqlight.exec("BEGIN IMMEDIATE", on: connection) {
        Error(error) -> Error(DatabaseFailure(string.inspect(error)))
        Ok(Nil) -> {
          let outcome = case
            replay_join(connection, public_id, digest, join_attempt_token)
          {
            Ok(Some(response)) -> Ok(response)
            Ok(None) ->
              case attempt_token_used(connection, digest) {
                Ok(True) -> Error(InvalidJoinAttempt)
                Ok(False) ->
                  create_ticket(
                    connection,
                    public_id,
                    digest,
                    join_attempt_token,
                  )
                Error(error) -> Error(error)
              }
            Error(error) -> Error(error)
          }
          case outcome {
            Ok(response) ->
              case sqlight.exec("COMMIT", on: connection) {
                Ok(Nil) -> Ok(response)
                Error(error) -> {
                  let _ = sqlight.exec("ROLLBACK", on: connection)
                  Error(DatabaseFailure(string.inspect(error)))
                }
              }
            Error(error) -> {
              let _ = sqlight.exec("ROLLBACK", on: connection)
              Error(error)
            }
          }
        }
      }
    }
  }
}

fn attempt_token_used(
  connection: sqlight.Connection,
  digest: String,
) -> Result(Bool, TicketError) {
  case
    sqlight.query(
      "SELECT count(*) FROM tracking_credentials WHERE token_digest = ?",
      on: connection,
      with: [sqlight.text(digest)],
      expecting: decode.list(decode.int),
    )
  {
    Ok([[count]]) -> Ok(count > 0)
    Ok(_) -> Error(DatabaseFailure("tracking credential lookup failed"))
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

pub fn track(
  connection: sqlight.Connection,
  token: String,
) -> Result(String, TicketError) {
  case valid_token(token) {
    False -> Error(QueueUnavailable)
    True ->
      case
        sqlight.query(
          "SELECT json_object('ticket_number', tickets.ticket_number, 'status', tickets.status, 'queue_position', CASE WHEN tickets.status = 'waiting' THEN 1 + (SELECT count(*) FROM tickets ahead WHERE ahead.queue_session_id = tickets.queue_session_id AND ahead.status = 'waiting' AND ahead.queue_sequence < tickets.queue_sequence) ELSE NULL END, 'queue', queues.name, 'service', services.name, 'location', locations.name) FROM tracking_credentials JOIN tickets ON tickets.id = tracking_credentials.ticket_id JOIN queues ON queues.id = tickets.queue_id JOIN services ON services.id = queues.service_id JOIN locations ON locations.id = queues.location_id WHERE tracking_credentials.token_digest = ? AND tracking_credentials.revoked_at IS NULL AND (tracking_credentials.expires_at IS NULL OR tracking_credentials.expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) LIMIT 1",
          on: connection,
          with: [sqlight.text(token_digest(token))],
          expecting: decode.list(decode.string),
        )
      {
        Ok([[details]]) -> Ok(details)
        Ok(_) -> Error(QueueUnavailable)
        Error(error) -> Error(DatabaseFailure(string.inspect(error)))
      }
  }
}

fn create_ticket(
  connection: sqlight.Connection,
  public_id: String,
  digest: String,
  token: String,
) -> Result(String, TicketError) {
  use target <- result.try(load_target(connection, public_id))
  case target.identity_policy {
    "anonymous" ->
      case over_capacity(target) {
        True -> Error(QueueFull)
        False -> insert_ticket(connection, target, digest, public_id, token)
      }
    _ -> Error(QueueRequiresName)
  }
}

fn insert_ticket(
  connection: sqlight.Connection,
  target: JoinTarget,
  digest: String,
  public_id: String,
  token: String,
) -> Result(String, TicketError) {
  let ticket_id = id.new()
  let event_id = id.new()
  let credential_id = id.new()
  use _ <- result.try(
    exec(
      connection,
      "UPDATE queue_sessions SET next_ticket_number = next_ticket_number + 1, next_queue_sequence = next_queue_sequence + 1 WHERE id = ? AND state = 'open' AND occurrence_status = 'active' RETURNING 1",
      [sqlight.text(target.session_id)],
    ),
  )
  use _ <- result.try(
    exec(
      connection,
      "INSERT INTO tickets (id, organization_id, queue_id, queue_session_id, ticket_number, queue_sequence, join_attempt_digest, status, identity_policy, joined_at, created_at, updated_at) VALUES (?, (SELECT organization_id FROM queues WHERE id = ?), ?, ?, ?, ?, ?, 'waiting', 'anonymous', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) RETURNING 1",
      [
        sqlight.text(ticket_id),
        sqlight.text(target.queue_id),
        sqlight.text(target.queue_id),
        sqlight.text(target.session_id),
        sqlight.int(target.ticket_number),
        sqlight.int(target.queue_sequence),
        sqlight.text(digest),
      ],
    ),
  )
  use _ <- result.try(
    exec(
      connection,
      "INSERT INTO ticket_events (id, ticket_id, from_status, to_status, actor_type, occurred_at, created_at) VALUES (?, ?, NULL, 'waiting', 'visitor', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) RETURNING 1",
      [sqlight.text(event_id), sqlight.text(ticket_id)],
    ),
  )
  use _ <- result.try(
    exec(
      connection,
      "INSERT INTO tracking_credentials (id, ticket_id, token_digest, created_at) VALUES (?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) RETURNING 1",
      [
        sqlight.text(credential_id),
        sqlight.text(ticket_id),
        sqlight.text(digest),
      ],
    ),
  )
  case replay_join(connection, public_id, digest, token) {
    Ok(Some(response)) -> Ok(response)
    Ok(None) -> Error(DatabaseFailure("created ticket could not be loaded"))
    Error(error) -> Error(error)
  }
}

fn replay_join(
  connection: sqlight.Connection,
  public_id: String,
  digest: String,
  token: String,
) -> Result(Option(String), TicketError) {
  case
    sqlight.query(
      "SELECT json_object('ticket_number', tickets.ticket_number, 'status', tickets.status, 'queue', queues.name, 'service', services.name, 'location', locations.name, 'tracking_token', ?) FROM tickets JOIN queues ON queues.id = tickets.queue_id JOIN services ON services.id = queues.service_id JOIN locations ON locations.id = queues.location_id WHERE queues.public_id = ? AND tickets.join_attempt_digest = ? LIMIT 1",
      on: connection,
      with: [sqlight.text(token), sqlight.text(public_id), sqlight.text(digest)],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[response]]) -> Ok(Some(response))
    Ok(_) -> Ok(None)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn load_target(
  connection: sqlight.Connection,
  public_id: String,
) -> Result(JoinTarget, TicketError) {
  case
    sqlight.query(
      "SELECT json_object('queue_id', queues.id, 'identity_policy', queues.identity_policy, 'session_id', sessions.id, 'ticket_number', sessions.next_ticket_number, 'queue_sequence', sessions.next_queue_sequence, 'queue_capacity', queues.active_ticket_capacity, 'occurrence_capacity', sessions.occurrence_ticket_cap, 'active_count', (SELECT count(*) FROM tickets WHERE queue_session_id = sessions.id AND status IN ('waiting', 'called', 'serving'))) FROM queues JOIN locations ON locations.id = queues.location_id JOIN services ON services.id = queues.service_id JOIN queue_sessions sessions ON sessions.id = (SELECT latest.id FROM queue_sessions latest WHERE latest.queue_id = queues.id ORDER BY latest.opened_at DESC, latest.id DESC LIMIT 1) WHERE queues.public_id = ? AND queues.is_active = 1 AND locations.is_active = 1 AND services.is_active = 1 AND sessions.state = 'open' AND sessions.occurrence_status = 'active' AND (sessions.signup_opens_at IS NULL OR sessions.signup_opens_at <= strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) LIMIT 1",
      on: connection,
      with: [sqlight.text(public_id)],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[payload]]) ->
      case json.parse(payload, join_target_decoder()) {
        Ok(target) -> Ok(target)
        Error(_) -> Error(DatabaseFailure("invalid queue data"))
      }
    Ok(_) -> Error(QueueUnavailable)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn join_target_decoder() -> decode.Decoder(JoinTarget) {
  use queue_id <- decode.field("queue_id", decode.string)
  use identity_policy <- decode.field("identity_policy", decode.string)
  use session_id <- decode.field("session_id", decode.string)
  use ticket_number <- decode.field("ticket_number", decode.int)
  use queue_sequence <- decode.field("queue_sequence", decode.int)
  use queue_capacity <- decode.field(
    "queue_capacity",
    decode.optional(decode.int),
  )
  use occurrence_capacity <- decode.field(
    "occurrence_capacity",
    decode.optional(decode.int),
  )
  use active_count <- decode.field("active_count", decode.int)
  decode.success(JoinTarget(
    queue_id:,
    identity_policy:,
    session_id:,
    ticket_number:,
    queue_sequence:,
    queue_capacity:,
    occurrence_capacity:,
    active_count:,
  ))
}

fn over_capacity(target: JoinTarget) -> Bool {
  case target.queue_capacity, target.occurrence_capacity {
    Some(capacity), _ if target.active_count >= capacity -> True
    _, Some(capacity) if target.active_count >= capacity -> True
    _, _ -> False
  }
}

fn exec(
  connection: sqlight.Connection,
  statement: String,
  parameters: List(sqlight.Value),
) -> Result(Nil, TicketError) {
  case
    sqlight.query(
      statement,
      on: connection,
      with: parameters,
      expecting: decode.list(decode.int),
    )
  {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn valid_token(token: String) -> Bool {
  string.length(token) >= 32 && string.length(token) <= 128
}

fn token_digest(token: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(token))
  |> bit_array.base16_encode
}

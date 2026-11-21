import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import server/database/parrot
import server/id
import server/sql
import shared.{type IdentityPolicy, Anonymous, NameRequired}
import sqlight

pub type TicketError {
  InvalidJoinAttempt
  QueueUnavailable
  CancellationNotAllowed
  FirstNameRequired
  LastNameRequired
  QueueFull
  DatabaseFailure(String)
}

type JoinTarget {
  JoinTarget(
    queue_id: String,
    identity_policy: IdentityPolicy,
    session_id: String,
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
  join_visitor(connection, public_id, join_attempt_token, None, None)
}

pub fn join_visitor(
  connection: sqlight.Connection,
  public_id: String,
  join_attempt_token: String,
  first_name: Option(String),
  last_name: Option(String),
) -> Result(String, TicketError) {
  use _ <- result.try(validate_join_attempt(join_attempt_token))
  let first_name = normalize_name(first_name)
  let last_name = normalize_name(last_name)
  let digest = token_digest(join_attempt_token)
  transaction(connection, fn() {
    join_in_transaction(
      connection,
      public_id,
      digest,
      join_attempt_token,
      first_name,
      last_name,
    )
  })
}

fn normalize_name(value: Option(String)) -> Option(String) {
  case value {
    Some(name) -> {
      let trimmed = string.trim(name)
      case trimmed == "" {
        True -> None
        False -> Some(trimmed)
      }
    }
    None -> None
  }
}

fn validate_join_attempt(token: String) -> Result(Nil, TicketError) {
  case valid_token(token) {
    True -> Ok(Nil)
    False -> Error(InvalidJoinAttempt)
  }
}

fn transaction(
  connection: sqlight.Connection,
  operation: fn() -> Result(value, TicketError),
) -> Result(value, TicketError) {
  use _ <- result.try(exec_transaction_command(connection, "BEGIN IMMEDIATE"))
  case operation() {
    Ok(value) ->
      case exec_transaction_command(connection, "COMMIT") {
        Ok(Nil) -> Ok(value)
        Error(error) -> {
          let _ = sqlight.exec("ROLLBACK", on: connection)
          Error(error)
        }
      }
    Error(error) -> {
      let _ = sqlight.exec("ROLLBACK", on: connection)
      Error(error)
    }
  }
}

fn exec_transaction_command(
  connection: sqlight.Connection,
  command: String,
) -> Result(Nil, TicketError) {
  sqlight.exec(command, on: connection)
  |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) })
}

fn join_in_transaction(
  connection: sqlight.Connection,
  public_id: String,
  digest: String,
  token: String,
  first_name: Option(String),
  last_name: Option(String),
) -> Result(String, TicketError) {
  use replayed <- result.try(replay_join(connection, public_id, digest, token))
  case replayed {
    Some(response) -> Ok(response)
    None -> {
      use used <- result.try(attempt_token_used(connection, digest))
      case used {
        True -> Error(InvalidJoinAttempt)
        False ->
          create_ticket(
            connection,
            public_id,
            digest,
            token,
            first_name,
            last_name,
          )
      }
    }
  }
}

fn attempt_token_used(
  connection: sqlight.Connection,
  digest: String,
) -> Result(Bool, TicketError) {
  case parrot.query(connection, sql.ticket_attempt_token_used(digest)) {
    Ok([row]) -> Ok(row.count > 0)
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
        parrot.query(connection, sql.track_visitor_ticket(token_digest(token)))
      {
        Ok([row]) -> Ok(row.payload)
        Ok(_) -> Error(QueueUnavailable)
        Error(error) -> Error(DatabaseFailure(string.inspect(error)))
      }
  }
}

/// Cancel a ticket using its private tracking credential. Cancellation is
/// allowed only while waiting; repeating a successful cancellation is safe.
pub fn cancel(
  connection: sqlight.Connection,
  token: String,
) -> Result(String, TicketError) {
  case valid_token(token) {
    False -> Error(QueueUnavailable)
    True ->
      transaction(connection, fn() { cancel_in_transaction(connection, token) })
  }
}

fn cancel_in_transaction(
  connection: sqlight.Connection,
  token: String,
) -> Result(String, TicketError) {
  case
    parrot.query(
      connection,
      sql.get_visitor_cancellation_ticket(token_digest(token)),
    )
  {
    Ok([sql.GetVisitorCancellationTicket(_, "cancelled")]) ->
      track(connection, token)
    Ok([sql.GetVisitorCancellationTicket(ticket_id, "waiting")]) -> {
      let event_id = id.new()
      use _ <- result.try(
        parrot.query(connection, sql.cancel_visitor_ticket(ticket_id))
        |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
      )
      use _ <- result.try(
        parrot.query(
          connection,
          sql.record_visitor_cancellation(event_id, ticket_id),
        )
        |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
      )
      track(connection, token)
    }
    Ok([_]) -> Error(CancellationNotAllowed)
    Ok(_) -> Error(QueueUnavailable)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn create_ticket(
  connection: sqlight.Connection,
  public_id: String,
  digest: String,
  token: String,
  first_name: Option(String),
  last_name: Option(String),
) -> Result(String, TicketError) {
  use target <- result.try(load_target(connection, public_id))
  case target.identity_policy {
    Anonymous -> {
      use <- bool.guard(over_capacity(target), Error(QueueFull))
      insert_ticket(connection, target, digest, public_id, token, None, None)
    }

    NameRequired -> {
      use first_name <- result.try(required_name(first_name, FirstNameRequired))
      use last_name <- result.try(required_name(last_name, LastNameRequired))
      use <- bool.guard(over_capacity(target), Error(QueueFull))
      insert_ticket(
        connection,
        target,
        digest,
        public_id,
        token,
        Some(first_name),
        Some(last_name),
      )
    }
  }
}

/// Atomically take the next ticket number and queue sequence for a session.
/// Matches zero rows if the session closed since `load_target`, which is
/// reported as `QueueUnavailable` rather than silently reusing stale numbers.
fn reserve_numbers(
  connection: sqlight.Connection,
  session_id: String,
) -> Result(#(Int, Int), TicketError) {
  case
    parrot.query(connection, sql.reserve_visitor_ticket_numbers(session_id))
  {
    Ok([row]) -> Ok(#(row.next_ticket_number - 1, row.next_queue_sequence - 1))
    Ok(_) -> Error(QueueUnavailable)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn insert_ticket(
  connection: sqlight.Connection,
  target: JoinTarget,
  digest: String,
  public_id: String,
  token: String,
  first_name: Option(String),
  last_name: Option(String),
) -> Result(String, TicketError) {
  let ticket_id = id.new()
  let event_id = id.new()
  let credential_id = id.new()

  use #(ticket_number, queue_sequence) <- result.try(reserve_numbers(
    connection,
    target.session_id,
  ))

  use _ <- result.try(
    parrot.query(
      connection,
      sql.create_visitor_ticket(
        ticket_id: ticket_id,
        queue_id: target.queue_id,
        session_id: target.session_id,
        ticket_number: ticket_number,
        queue_sequence: queue_sequence,
        digest: digest,
        identity_policy: case target.identity_policy {
          Anonymous -> "anonymous"
          NameRequired -> "name_required"
        },
        first_name: first_name,
        last_name: last_name,
      ),
    )
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  use _ <- result.try(
    parrot.query(connection, sql.record_visitor_join(event_id, ticket_id))
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  use _ <- result.try(
    parrot.query(
      connection,
      sql.create_visitor_tracking_credential(credential_id, ticket_id, digest),
    )
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  case replay_join(connection, public_id, digest, token) {
    Ok(Some(response)) -> Ok(response)
    Ok(None) -> Error(DatabaseFailure("created ticket could not be loaded"))
    Error(error) -> Error(error)
  }
}

fn required_name(
  value: Option(String),
  error: TicketError,
) -> Result(String, TicketError) {
  case value {
    Some(name) -> Ok(name)
    None -> Error(error)
  }
}

fn replay_join(
  connection: sqlight.Connection,
  public_id: String,
  digest: String,
  token: String,
) -> Result(Option(String), TicketError) {
  case
    parrot.query(connection, sql.replay_visitor_join(token, public_id, digest))
  {
    Ok([row]) -> Ok(Some(row.payload))
    Ok(_) -> Ok(None)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn load_target(
  connection: sqlight.Connection,
  public_id: String,
) -> Result(JoinTarget, TicketError) {
  case parrot.query(connection, sql.get_visitor_join_target(public_id)) {
    Ok([row]) -> {
      use identity_policy <- result.try(case row.identity_policy {
        "anonymous" -> Ok(Anonymous)
        "name_required" -> Ok(NameRequired)
        _ -> Error(DatabaseFailure("invalid queue data"))
      })
      Ok(JoinTarget(
        queue_id: row.queue_id,
        identity_policy: identity_policy,
        session_id: row.session_id,
        queue_capacity: row.queue_capacity,
        occurrence_capacity: row.occurrence_capacity,
        active_count: row.active_count,
      ))
    }
    Ok(_) -> Error(QueueUnavailable)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn over_capacity(target: JoinTarget) -> Bool {
  [target.queue_capacity, target.occurrence_capacity]
  |> option.values
  |> list.any(fn(capacity) { target.active_count >= capacity })
}

fn valid_token(token: String) -> Bool {
  string.length(token) >= 32 && string.length(token) <= 128
}

fn token_digest(token: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(token))
  |> bit_array.base16_encode
}

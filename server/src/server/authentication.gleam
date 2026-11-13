import argus
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/option.{Some}
import gleam/result
import gleam/string
import server/database/query
import sqlight

pub type User {
  User(id: String, name: String, email: String)
}

pub type Session {
  Session(user: User, token: String)
}

pub type SignInError {
  InvalidCredentials
  DatabaseFailure(String)
}

/// Authenticate a credential account and persist a 30-day session.
/// Password hashes and raw session tokens are never returned as user data.
pub fn sign_in(
  connection: sqlight.Connection,
  email: String,
  password: String,
) -> Result(Session, SignInError) {
  let normalized_email = email |> string.trim |> string.lowercase
  use password_hash <- result.try(load_password_hash(
    connection,
    normalized_email,
  ))
  use verified <- result.try(verify_password(password_hash, password))
  case verified {
    False -> Error(InvalidCredentials)
    True -> {
      use user <- result.try(load_user(connection, normalized_email))
      let token = new_token()
      use _ <- result.try(create_session(connection, user.id, token))
      Ok(Session(user:, token:))
    }
  }
}

/// Resolve an unexpired session token to its user. Missing and expired
/// sessions share the invalid-credentials result so callers do not expose
/// whether a token was previously valid.
pub fn user_for_session(
  connection: sqlight.Connection,
  token: String,
) -> Result(String, SignInError) {
  case
    sqlight.query(
      "SELECT user_id FROM sessions WHERE token = ? AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now') LIMIT 1",
      on: connection,
      with: [sqlight.text(token)],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[user_id]]) -> Ok(user_id)
    Ok(_) -> Error(InvalidCredentials)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Revoke a session token. A missing token is treated as a successful no-op.
pub fn sign_out(
  connection: sqlight.Connection,
  token: String,
) -> Result(Nil, SignInError) {
  case
    sqlight.query(
      "DELETE FROM sessions WHERE token = ?",
      on: connection,
      with: [sqlight.text(token)],
      expecting: decode.list(decode.string),
    )
  {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn load_password_hash(
  connection: sqlight.Connection,
  email: String,
) -> Result(String, SignInError) {
  case
    sqlight.query(
      "SELECT accounts.password FROM accounts INNER JOIN users ON users.id = accounts.user_id WHERE lower(trim(users.email)) = ? AND accounts.provider_id = 'credential' AND accounts.password IS NOT NULL LIMIT 1",
      on: connection,
      with: [sqlight.text(email)],
      expecting: decode.list(decode.optional(decode.string)),
    )
  {
    Ok([[Some(password_hash)]]) -> Ok(password_hash)
    Ok(_) -> Error(InvalidCredentials)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn verify_password(
  password_hash: String,
  password: String,
) -> Result(Bool, SignInError) {
  case argus.verify(password_hash, password) {
    Ok(verified) -> Ok(verified)
    Error(_) -> Error(InvalidCredentials)
  }
}

fn load_user(
  connection: sqlight.Connection,
  email: String,
) -> Result(User, SignInError) {
  use ids <- result.try(query.strings(
    connection,
    "SELECT id FROM users WHERE lower(trim(email)) = ? LIMIT 1",
    [sqlight.text(email)],
    DatabaseFailure,
  ))
  use names <- result.try(query.strings(
    connection,
    "SELECT name FROM users WHERE lower(trim(email)) = ? LIMIT 1",
    [sqlight.text(email)],
    DatabaseFailure,
  ))
  use emails <- result.try(query.strings(
    connection,
    "SELECT email FROM users WHERE lower(trim(email)) = ? LIMIT 1",
    [sqlight.text(email)],
    DatabaseFailure,
  ))
  case ids, names, emails {
    [[id]], [[name]], [[stored_email]] -> Ok(User(id, name, stored_email))
    _, _, _ -> Error(InvalidCredentials)
  }
}

fn create_session(
  connection: sqlight.Connection,
  user_id: String,
  token: String,
) -> Result(Nil, SignInError) {
  case
    sqlight.query(
      "INSERT INTO sessions (id, expires_at, token, created_at, updated_at, user_id) VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+30 days'), ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?) RETURNING id",
      on: connection,
      with: [
        sqlight.text(new_token()),
        sqlight.text(token),
        sqlight.text(user_id),
      ],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(DatabaseFailure("session was not created"))
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn new_token() -> String {
  crypto.strong_random_bytes(32)
  |> bit_array.base64_url_encode(False)
}

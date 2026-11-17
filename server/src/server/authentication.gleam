import argus
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/result
import gleam/string

import sqlight

pub type User {
  User(id: String, name: String, email: String)
}

type Credential {
  Credential(user: User, password_hash: String)
}

pub type Session {
  Session(user: User, token: String)
}

pub type AuthError {
  InvalidCredentials
  DatabaseFailure(String)
}

/// SQLite expression for the current UTC time in the format used by the schema.
const now_sql = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"

fn hash_token(token: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(token))
  |> bit_array.base16_encode
}

/// Authenticate a credential account and persist a 30-day session.
/// Password hashes and raw session tokens are never returned as user data.
pub fn sign_in(
  connection: sqlight.Connection,
  email: String,
  password: String,
) -> Result(Session, AuthError) {
  let normalized_email = email |> string.trim |> string.lowercase
  use credential <- result.try(load_user(connection, normalized_email))
  use verified <- result.try(verify_password(credential.password_hash, password))
  case verified {
    False -> Error(InvalidCredentials)
    True -> {
      let token = new_token()
      use _ <- result.try(create_session(connection, credential.user.id, token))
      Ok(Session(user: credential.user, token: token))
    }
  }
}

/// Resolve an unexpired session token to its user. Missing and expired
/// sessions share the invalid-credentials result so callers do not expose
/// whether a token was previously valid.
pub fn user_for_session(
  connection: sqlight.Connection,
  token: String,
) -> Result(String, AuthError) {
  let token_digest = hash_token(token)
  case
    sqlight.query(
      "SELECT user_id FROM sessions WHERE token = ? AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now') LIMIT 1",
      on: connection,
      with: [sqlight.text(token_digest)],
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
) -> Result(Nil, AuthError) {
  let token_digest = hash_token(token)
  sqlight.query(
    "DELETE FROM sessions WHERE token = ?",
    on: connection,
    with: [sqlight.text(token_digest)],
    expecting: decode.success(Nil),
  )
  |> result.replace(Nil)
  |> result.map_error(database_failure)
}

fn verify_password(
  password_hash: String,
  password: String,
) -> Result(Bool, AuthError) {
  case argus.verify(password_hash, password) {
    Ok(verified) -> Ok(verified)
    Error(_) -> Error(InvalidCredentials)
  }
}

fn load_user(
  connection: sqlight.Connection,
  email: String,
) -> Result(Credential, AuthError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use name <- decode.field(1, decode.string)
    use stored_email <- decode.field(2, decode.string)
    use password_hash <- decode.field(3, decode.string)
    decode.success(Credential(
      user: User(id:, name:, email: stored_email),
      password_hash:,
    ))
  }

  let query =
    "SELECT users.id, users.name, users.email, accounts.password
       FROM users INNER JOIN accounts ON accounts.user_id = users.id
       WHERE lower(trim(users.email)) = ?
         AND accounts.provider_id = 'credential'
         AND accounts.password IS NOT NULL
       LIMIT 1"

  case
    sqlight.query(
      query,
      on: connection,
      with: [sqlight.text(email)],
      expecting: decoder,
    )
  {
    Ok([credential]) -> Ok(credential)
    Ok(_) -> Error(InvalidCredentials)
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

fn create_session(
  connection: sqlight.Connection,
  user_id: String,
  token: String,
) -> Result(Nil, AuthError) {
  let token_digest = hash_token(token)
  case
    sqlight.query(
      "INSERT INTO sessions (id, expires_at, token, created_at, updated_at, user_id)
       VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+30 days'), ?, "
        <> now_sql
        <> ", "
        <> now_sql
        <> ", ?)
       RETURNING id",
      on: connection,
      with: [
        sqlight.text(new_token()),
        sqlight.text(token_digest),
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

fn database_failure(error: sqlight.Error) -> AuthError {
  DatabaseFailure(string.inspect(error))
}

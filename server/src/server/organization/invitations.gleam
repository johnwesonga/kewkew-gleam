import argus
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import server/database/query
import server/id
import server/organization/access
import sqlight

pub type InviteError {
  InvalidInvitation
  Forbidden
  NotFound
  Conflict
  DatabaseFailure(String)
}

pub type InviteResult {
  InviteResult(
    id: String,
    token: String,
    email: String,
    role: String,
    expires_at: String,
  )
}

/// Return delivery-confirmed invitations for organization administrators.
/// Secret token digests are intentionally excluded from the selected fields.
pub fn list_sent(
  connection: sqlight.Connection,
  user_id: String,
  organization_id: String,
) -> Result(String, InviteError) {
  use _ <- result.try(access.require_admin(
    connection,
    user_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  use rows <- result.try(query.strings(
    connection,
    "SELECT 
    json_object('id', id, 
    'organization_id', organization_id, 
    'invited_email', invited_email, 
    'role', role, 
    'location_ids', json(location_ids_json), 
    'created_by_user_id', created_by_user_id, 
    'created_at', created_at, 
    'expires_at', expires_at, 
    'delivery_state', delivery_state, 
    'accepted_by_user_id', accepted_by_user_id, 
    'accepted_at', accepted_at, 
    'revoked_at', revoked_at) 
    FROM 
    staff_invitations WHERE organization_id = ? 
    AND delivery_state = 'sent' 
    ORDER BY created_at DESC",
    [sqlight.text(organization_id)],
    DatabaseFailure,
  ))
  Ok(
    "["
    <> string.join(
      list.map(rows, fn(row) {
        let assert [json] = row
        json
      }),
      ",",
    )
    <> "]",
  )
}

pub type AcceptError {
  InvalidOrExpired
  ExistingIdentityNeedsSignIn
  PasswordRejected
  AcceptDatabaseFailure(String)
}

/// Create a pending single-use, seven-day invitation. Delivery is performed by
/// the HTTP layer and the raw token is returned only for that attempt.
pub fn create(
  connection: sqlight.Connection,
  inviter_id: String,
  organization_id: String,
  email: String,
  role: String,
  location_ids: List(String),
) -> Result(InviteResult, InviteError) {
  let email = email |> string.trim |> string.lowercase
  let location_ids = list.unique(location_ids)
  use _ <- result.try(validate(email, role, location_ids))
  use _ <- result.try(access.require_admin(
    connection,
    inviter_id,
    organization_id,
    NotFound,
    Forbidden,
    DatabaseFailure,
  ))
  use _ <- result.try(validate_locations(
    connection,
    organization_id,
    role,
    location_ids,
  ))
  let token =
    crypto.strong_random_bytes(32) |> bit_array.base64_url_encode(False)
  let digest =
    crypto.hash(crypto.Sha256, <<token:utf8>>)
    |> bit_array.base64_url_encode(False)
  let invitation_id = id.new()
  case
    sqlight.query(
      "INSERT INTO staff_invitations 
      (id, organization_id, invited_email, role, location_ids_json, token_digest, created_by_user_id, created_at, expires_at, delivery_state) 
      VALUES (?, ?, ?, ?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+7 days'), 'failed') RETURNING expires_at",
      on: connection,
      with: [
        sqlight.text(invitation_id),
        sqlight.text(organization_id),
        sqlight.text(email),
        sqlight.text(role),
        sqlight.text(encode_locations(location_ids)),
        sqlight.text(digest),
        sqlight.text(inviter_id),
      ],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[expires_at]]) ->
      Ok(InviteResult(invitation_id, token, email, role, expires_at))
    Ok(_) -> Error(DatabaseFailure("invitation was not created"))
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Record the result of the provider call. Invitations start in the schema's
/// existing failed state and become usable only after successful delivery.
pub fn set_delivery_state(
  connection: sqlight.Connection,
  invitation_id: String,
  state: String,
) -> Result(Nil, InviteError) {
  case state {
    "sent" | "failed" ->
      case
        sqlight.query(
          "UPDATE staff_invitations SET delivery_state = ? WHERE id = ? AND delivery_state = 'failed' RETURNING id",
          on: connection,
          with: [sqlight.text(state), sqlight.text(invitation_id)],
          expecting: decode.list(decode.string),
        )
      {
        Ok([[_]]) -> Ok(Nil)
        Ok(_) -> Error(NotFound)
        Error(error) -> Error(DatabaseFailure(string.inspect(error)))
      }
    _ -> Error(InvalidInvitation)
  }
}

/// Accept an invitation and establish the invitee's credential account in one
/// transaction. Existing identities must sign in first; this avoids taking
/// over an account merely by receiving an invitation email.
pub fn accept(
  connection: sqlight.Connection,
  token: String,
  name: String,
  password: String,
) -> Result(Nil, AcceptError) {
  let name = string.trim(name)
  case name, string.length(password) >= 12 {
    "", _ -> Error(PasswordRejected)
    _, False -> Error(PasswordRejected)
    _, True -> {
      use password_hash <- result.try(
        case argus.hash(argus.hasher(), password) {
          Ok(hash) -> Ok(hash.encoded_hash)
          Error(_) -> Error(PasswordRejected)
        },
      )
      accept_transaction(connection, token, name, password_hash)
    }
  }
}

/// Accept an invitation for an existing identity after that identity has
/// authenticated. The supplied user must own the invited email address.
pub fn accept_for_user(
  connection: sqlight.Connection,
  token: String,
  user_id: String,
) -> Result(Nil, AcceptError) {
  accept_existing_transaction(connection, token, user_id)
}

fn accept_transaction(
  connection: sqlight.Connection,
  token: String,
  name: String,
  password_hash: String,
) -> Result(Nil, AcceptError) {
  use _ <- result.try(
    sqlight.exec("BEGIN IMMEDIATE", on: connection)
    |> result.map_error(fn(error) {
      AcceptDatabaseFailure(string.inspect(error))
    }),
  )
  let accepted = accept_rows(connection, token, name, password_hash)
  case accepted {
    Ok(Nil) ->
      case sqlight.exec("COMMIT", on: connection) {
        Ok(Nil) -> Ok(Nil)
        Error(error) -> {
          let _ = sqlight.exec("ROLLBACK", on: connection)
          Error(AcceptDatabaseFailure(string.inspect(error)))
        }
      }
    Error(error) -> {
      let _ = sqlight.exec("ROLLBACK", on: connection)
      Error(error)
    }
  }
}

fn accept_rows(
  connection: sqlight.Connection,
  token: String,
  name: String,
  password_hash: String,
) -> Result(Nil, AcceptError) {
  let digest =
    crypto.hash(crypto.Sha256, <<token:utf8>>)
    |> bit_array.base64_url_encode(False)
  use rows <- result.try(query.strings(
    connection,
    "SELECT id, organization_id, invited_email, role, location_ids_json FROM staff_invitations WHERE token_digest = ? AND delivery_state = 'sent' AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
    [sqlight.text(digest)],
    AcceptDatabaseFailure,
  ))
  case rows {
    [[invitation_id, organization_id, email, role, locations_json]] -> {
      use existing <- result.try(
        sqlight.query(
          "SELECT id FROM users WHERE email = ? COLLATE NOCASE LIMIT 1",
          on: connection,
          with: [sqlight.text(email)],
          expecting: decode.list(decode.string),
        )
        |> result.map_error(fn(error) {
          AcceptDatabaseFailure(string.inspect(error))
        }),
      )
      case existing {
        [[_]] -> Error(ExistingIdentityNeedsSignIn)
        [] ->
          create_invitee(
            connection,
            invitation_id,
            organization_id,
            email,
            role,
            locations_json,
            name,
            password_hash,
          )
        _ -> Error(InvalidOrExpired)
      }
    }
    _ -> Error(InvalidOrExpired)
  }
}

fn create_invitee(
  connection: sqlight.Connection,
  invitation_id: String,
  organization_id: String,
  email: String,
  role: String,
  locations_json: String,
  name: String,
  password_hash: String,
) -> Result(Nil, AcceptError) {
  let user_id = id.new()
  let account_id = id.new()
  use _ <- result.try(
    insert(
      connection,
      "INSERT INTO users (id, name, email, email_verified) VALUES (?, ?, ?, 0) RETURNING id",
      [sqlight.text(user_id), sqlight.text(name), sqlight.text(email)],
    ),
  )
  use _ <- result.try(
    insert(
      connection,
      "INSERT INTO accounts (id, account_id, provider_id, user_id, password, created_at, updated_at) VALUES (?, ?, 'credential', ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) RETURNING id",
      [
        sqlight.text(account_id),
        sqlight.text(user_id),
        sqlight.text(user_id),
        sqlight.text(password_hash),
      ],
    ),
  )
  use _ <- result.try(
    insert(
      connection,
      "INSERT INTO organization_memberships (organization_id, user_id, role, status) VALUES (?, ?, ?, 'active') ON CONFLICT (organization_id, user_id) DO UPDATE SET role = excluded.role, status = 'active', updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') RETURNING user_id",
      [sqlight.text(organization_id), sqlight.text(user_id), sqlight.text(role)],
    ),
  )
  use _ <- result.try(insert_locations(
    connection,
    organization_id,
    user_id,
    role,
    locations_json,
  ))
  use _ <- result.try(
    insert(
      connection,
      "UPDATE staff_invitations SET accepted_by_user_id = ?, accepted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ? AND accepted_at IS NULL RETURNING id",
      [sqlight.text(user_id), sqlight.text(invitation_id)],
    ),
  )
  insert(
    connection,
    "INSERT INTO membership_audit_events (id, organization_id, actor_user_id, subject_user_id, change_type, after_role, after_status, details_json) SELECT ?, ?, created_by_user_id, ?, 'invitation_accepted', ?, 'active', json_object('invitation_id', ?) FROM staff_invitations WHERE id = ? RETURNING id",
    [
      sqlight.text(id.new()),
      sqlight.text(organization_id),
      sqlight.text(user_id),
      sqlight.text(role),
      sqlight.text(invitation_id),
      sqlight.text(invitation_id),
    ],
  )
}

fn accept_existing_transaction(
  connection: sqlight.Connection,
  token: String,
  user_id: String,
) -> Result(Nil, AcceptError) {
  use _ <- result.try(
    sqlight.exec("BEGIN IMMEDIATE", on: connection)
    |> result.map_error(fn(error) {
      AcceptDatabaseFailure(string.inspect(error))
    }),
  )
  let accepted = accept_existing_rows(connection, token, user_id)
  case accepted {
    Ok(Nil) ->
      case sqlight.exec("COMMIT", on: connection) {
        Ok(Nil) -> Ok(Nil)
        Error(error) -> {
          let _ = sqlight.exec("ROLLBACK", on: connection)
          Error(AcceptDatabaseFailure(string.inspect(error)))
        }
      }
    Error(error) -> {
      let _ = sqlight.exec("ROLLBACK", on: connection)
      Error(error)
    }
  }
}

fn accept_existing_rows(
  connection: sqlight.Connection,
  token: String,
  user_id: String,
) -> Result(Nil, AcceptError) {
  let digest =
    crypto.hash(crypto.Sha256, <<token:utf8>>)
    |> bit_array.base64_url_encode(False)
  use rows <- result.try(query.strings(
    connection,
    "SELECT id, organization_id, invited_email, role, location_ids_json FROM staff_invitations WHERE token_digest = ? AND delivery_state = 'sent' AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
    [sqlight.text(digest)],
    AcceptDatabaseFailure,
  ))
  case rows {
    [[invitation_id, organization_id, email, role, locations_json]] -> {
      use emails <- result.try(query.strings(
        connection,
        "SELECT email FROM users WHERE id = ? LIMIT 1",
        [sqlight.text(user_id)],
        AcceptDatabaseFailure,
      ))
      case emails {
        [[actual_email]] ->
          case string.lowercase(actual_email) == email {
            True ->
              activate_existing(
                connection,
                invitation_id,
                organization_id,
                user_id,
                role,
                locations_json,
              )
            False -> Error(InvalidOrExpired)
          }
        _ -> Error(InvalidOrExpired)
      }
    }
    _ -> Error(InvalidOrExpired)
  }
}

fn activate_existing(
  connection: sqlight.Connection,
  invitation_id: String,
  organization_id: String,
  user_id: String,
  role: String,
  locations_json: String,
) -> Result(Nil, AcceptError) {
  use _ <- result.try(
    insert(
      connection,
      "INSERT INTO organization_memberships (organization_id, user_id, role, status) VALUES (?, ?, ?, 'active') ON CONFLICT (organization_id, user_id) DO UPDATE SET role = excluded.role, status = 'active', updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') RETURNING user_id",
      [sqlight.text(organization_id), sqlight.text(user_id), sqlight.text(role)],
    ),
  )
  use _ <- result.try(
    sqlight.exec(
      "DELETE FROM membership_location_access WHERE organization_id = ? AND user_id = ?",
      on: connection,
    )
    |> result.map_error(fn(error) {
      AcceptDatabaseFailure(string.inspect(error))
    }),
  )
  use _ <- result.try(insert_locations(
    connection,
    organization_id,
    user_id,
    role,
    locations_json,
  ))
  use _ <- result.try(
    insert(
      connection,
      "UPDATE staff_invitations SET accepted_by_user_id = ?, accepted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ? AND accepted_at IS NULL RETURNING id",
      [sqlight.text(user_id), sqlight.text(invitation_id)],
    ),
  )
  insert(
    connection,
    "INSERT INTO membership_audit_events (id, organization_id, actor_user_id, subject_user_id, change_type, after_role, after_status, details_json) SELECT ?, ?, created_by_user_id, ?, 'invitation_accepted', ?, 'active', json_object('invitation_id', ?) FROM staff_invitations WHERE id = ? RETURNING id",
    [
      sqlight.text(id.new()),
      sqlight.text(organization_id),
      sqlight.text(user_id),
      sqlight.text(role),
      sqlight.text(invitation_id),
      sqlight.text(invitation_id),
    ],
  )
}

fn insert_locations(
  connection: sqlight.Connection,
  organization_id: String,
  user_id: String,
  role: String,
  locations_json: String,
) -> Result(Nil, AcceptError) {
  case role {
    "admin" -> Ok(Nil)
    _ ->
      case json_location_ids(locations_json) {
        Ok(ids) ->
          insert_location_ids(connection, organization_id, user_id, ids)
        Error(_) -> Error(InvalidOrExpired)
      }
  }
}

fn insert_location_ids(
  connection: sqlight.Connection,
  organization_id: String,
  user_id: String,
  ids: List(String),
) -> Result(Nil, AcceptError) {
  case ids {
    [] -> Ok(Nil)
    [location_id, ..rest] -> {
      use _ <- result.try(
        insert(
          connection,
          "INSERT INTO membership_location_access (organization_id, user_id, location_id) VALUES (?, ?, ?) RETURNING location_id",
          [
            sqlight.text(organization_id),
            sqlight.text(user_id),
            sqlight.text(location_id),
          ],
        ),
      )
      insert_location_ids(connection, organization_id, user_id, rest)
    }
  }
}

fn validate(
  email: String,
  role: String,
  location_ids: List(String),
) -> Result(Nil, InviteError) {
  let valid_role = case role {
    "admin" | "operator" -> True
    _ -> False
  }
  let valid_locations = case role {
    "admin" -> True
    _ -> location_ids != []
  }
  case string.contains(email, "@") && valid_role && valid_locations {
    True -> Ok(Nil)
    False -> Error(InvalidInvitation)
  }
}

fn validate_locations(
  connection: sqlight.Connection,
  organization_id: String,
  role: String,
  location_ids: List(String),
) -> Result(Nil, InviteError) {
  case role {
    "admin" -> Ok(Nil)
    _ -> {
      let expected = list.length(location_ids)
      case
        sqlight.query(
          "SELECT COUNT(*) FROM locations WHERE organization_id = ? AND id IN ("
            <> placeholders(list.length(location_ids))
            <> ")",
          on: connection,
          with: [
            sqlight.text(organization_id),
            ..list.map(location_ids, sqlight.text)
          ],
          expecting: decode.list(decode.int),
        )
      {
        Ok([[count]]) ->
          case count == expected {
            True -> Ok(Nil)
            False -> Error(InvalidInvitation)
          }
        Ok(_) -> Error(InvalidInvitation)
        Error(error) -> Error(DatabaseFailure(string.inspect(error)))
      }
    }
  }
}

fn insert(
  connection: sqlight.Connection,
  sql: String,
  args: List(sqlight.Value),
) -> Result(Nil, AcceptError) {
  case
    sqlight.query(
      sql,
      on: connection,
      with: args,
      expecting: decode.list(decode.string),
    )
  {
    Ok([[_]]) -> Ok(Nil)
    Ok(_) -> Error(InvalidOrExpired)
    Error(error) -> Error(AcceptDatabaseFailure(string.inspect(error)))
  }
}

fn encode_locations(ids: List(String)) -> String {
  "["
  <> string.join(list.map(ids, fn(value) { "\"" <> value <> "\"" }), ",")
  <> "]"
}

fn json_location_ids(value: String) -> Result(List(String), Nil) {
  json.parse(value, decode.list(decode.string))
  |> result.replace_error(Nil)
}

fn placeholders(count: Int) -> String {
  case count {
    0 -> "NULL"
    1 -> "?"
    _ -> "?," <> placeholders(count - 1)
  }
}

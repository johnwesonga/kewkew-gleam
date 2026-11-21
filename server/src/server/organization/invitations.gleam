import argus
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import server/database/parrot
import server/id
import server/organization/access
import server/organization/members
import server/sql
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
  use rows <- result.try(
    parrot.query(connection, sql.list_sent_staff_invitations(organization_id))
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  Ok("[" <> string.join(list.map(rows, fn(row) { row.payload }), ",") <> "]")
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
  invitation_transaction(connection, fn() {
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
    use _ <- result.try(
      parrot.query(
        connection,
        sql.retire_unusable_invitations(organization_id, email),
      )
      |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
    )
    use rows <- result.try(
      parrot.query(
        connection,
        sql.count_open_invitations(organization_id, email),
      )
      |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
    )
    case rows {
      [sql.CountOpenInvitations(0)] ->
        insert_invitation(
          connection,
          inviter_id,
          organization_id,
          email,
          role,
          location_ids,
        )
      _ -> Error(Conflict)
    }
  })
}

fn invitation_transaction(
  connection: sqlight.Connection,
  run: fn() -> Result(value, InviteError),
) -> Result(value, InviteError) {
  use _ <- result.try(
    sqlight.exec("BEGIN IMMEDIATE", on: connection)
    |> result.map_error(fn(error) { DatabaseFailure(string.inspect(error)) }),
  )
  case run() {
    Ok(value) ->
      case sqlight.exec("COMMIT", on: connection) {
        Ok(Nil) -> Ok(value)
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

fn insert_invitation(
  connection: sqlight.Connection,
  inviter_id: String,
  organization_id: String,
  email: String,
  role: String,
  location_ids: List(String),
) -> Result(InviteResult, InviteError) {
  let token =
    crypto.strong_random_bytes(32) |> bit_array.base64_url_encode(False)
  let digest =
    crypto.hash(crypto.Sha256, <<token:utf8>>)
    |> bit_array.base64_url_encode(False)
  let invitation_id = id.new()
  case
    parrot.query(
      connection,
      sql.create_staff_invitation(
        invitation_id,
        organization_id,
        email,
        role,
        encode_locations(location_ids),
        digest,
        inviter_id,
      ),
    )
  {
    Ok([row]) ->
      Ok(InviteResult(invitation_id, token, email, role, row.expires_at))
    Ok(_) -> Error(DatabaseFailure("invitation was not created"))
    Error(error) -> Error(DatabaseFailure(string.inspect(error)))
  }
}

/// Record the result of the provider call. Invitations start in the schema's
/// pending state and become usable only after successful delivery.
pub fn set_delivery_state(
  connection: sqlight.Connection,
  invitation_id: String,
  state: String,
) -> Result(Nil, InviteError) {
  case state {
    "sent" | "failed" ->
      case
        parrot.query(
          connection,
          sql.set_invitation_delivery_state(state, invitation_id),
        )
      {
        Ok([_]) -> Ok(Nil)
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
  use rows <- result.try(
    parrot.query(connection, sql.get_acceptable_staff_invitation(digest))
    |> result.map_error(fn(error) {
      AcceptDatabaseFailure(string.inspect(error))
    }),
  )
  case rows {
    [row] -> {
      let invitation_id = row.id
      let organization_id = row.organization_id
      let email = row.invited_email
      let role = row.role
      let locations_json = row.location_ids_json
      use existing <- result.try(
        parrot.query(connection, sql.get_invitation_identity_by_email(email))
        |> result.map_error(fn(error) {
          AcceptDatabaseFailure(string.inspect(error))
        }),
      )
      case existing {
        [_] -> Error(ExistingIdentityNeedsSignIn)
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
    accepted_write(parrot.query(
      connection,
      sql.create_invited_user(user_id, name, email),
    )),
  )
  use _ <- result.try(
    accepted_write(parrot.query(
      connection,
      sql.create_invited_credential(account_id, user_id, password_hash),
    )),
  )
  use _ <- result.try(
    accepted_write(parrot.query(
      connection,
      sql.activate_invited_membership(organization_id, user_id, role),
    )),
  )
  use _ <- result.try(insert_locations(
    connection,
    organization_id,
    user_id,
    role,
    locations_json,
  ))
  use _ <- result.try(
    accepted_write(parrot.query(
      connection,
      sql.mark_staff_invitation_accepted(user_id, invitation_id),
    )),
  )
  accepted_write(parrot.query(
    connection,
    sql.record_invitation_acceptance(
      id.new(),
      organization_id,
      user_id,
      role,
      invitation_id,
    ),
  ))
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
  use rows <- result.try(
    parrot.query(connection, sql.get_acceptable_staff_invitation(digest))
    |> result.map_error(fn(error) {
      AcceptDatabaseFailure(string.inspect(error))
    }),
  )
  case rows {
    [row] -> {
      let invitation_id = row.id
      let organization_id = row.organization_id
      let email = row.invited_email
      let role = row.role
      let locations_json = row.location_ids_json
      use emails <- result.try(
        parrot.query(connection, sql.get_invitation_identity_email(user_id))
        |> result.map_error(fn(error) {
          AcceptDatabaseFailure(string.inspect(error))
        }),
      )
      case emails {
        [row] ->
          case string.lowercase(row.email) == email {
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
  use _ <- result.try(case role {
    "operator" ->
      members.protect_last_administrator(connection, organization_id, user_id)
      |> result.map_error(fn(_) { InvalidOrExpired })
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    accepted_write(parrot.query(
      connection,
      sql.activate_invited_membership(organization_id, user_id, role),
    )),
  )
  use _ <- result.try(
    parrot.query(
      connection,
      sql.clear_invitee_location_access(organization_id, user_id),
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
    accepted_write(parrot.query(
      connection,
      sql.mark_staff_invitation_accepted(user_id, invitation_id),
    )),
  )
  accepted_write(parrot.query(
    connection,
    sql.record_invitation_acceptance(
      id.new(),
      organization_id,
      user_id,
      role,
      invitation_id,
    ),
  ))
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
        accepted_write(parrot.query(
          connection,
          sql.assign_invited_location(organization_id, user_id, location_id),
        )),
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
      use _ <- result.try(
        list.try_map(location_ids, fn(location_id) {
          case
            parrot.query(
              connection,
              sql.count_invitation_location(organization_id, location_id),
            )
          {
            Ok([sql.CountInvitationLocation(1)]) -> Ok(Nil)
            Ok(_) -> Error(InvalidInvitation)
            Error(error) -> Error(DatabaseFailure(string.inspect(error)))
          }
        }),
      )
      Ok(Nil)
    }
  }
}

fn accepted_write(
  result: Result(List(row), sqlight.Error),
) -> Result(Nil, AcceptError) {
  case result {
    Ok([_]) -> Ok(Nil)
    Ok(_) -> Error(InvalidOrExpired)
    Error(error) -> Error(AcceptDatabaseFailure(string.inspect(error)))
  }
}

fn encode_locations(ids: List(String)) -> String {
  json.array(ids, json.string) |> json.to_string
}

fn json_location_ids(value: String) -> Result(List(String), Nil) {
  json.parse(value, decode.list(decode.string))
  |> result.replace_error(Nil)
}

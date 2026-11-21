import gleam/dynamic/decode
import shared.{
  type MembershipRole, type MembershipStatus, Active, Admin, Operator, Suspended,
}

/// Staff administration contract, excluding credential and session data.
pub type Member {
  Member(
    organization_id: String,
    user_id: String,
    name: String,
    email: String,
    role: MembershipRole,
    status: MembershipStatus,
  )
}

pub fn decoder() -> decode.Decoder(Member) {
  use organization_id <- decode.field("organization_id", decode.string)
  use user_id <- decode.field("user_id", decode.string)
  use name <- decode.field("name", decode.string)
  use email <- decode.field("email", decode.string)
  use role <- decode.field(
    "role",
    decode.then(decode.string, fn(value) {
      case value {
        "admin" -> decode.success(Admin)
        "operator" -> decode.success(Operator)
        _ -> decode.failure(Admin, "MembershipRole")
      }
    }),
  )
  use status <- decode.field(
    "status",
    decode.then(decode.string, fn(value) {
      case value {
        "active" -> decode.success(Active)
        "suspended" -> decode.success(Suspended)
        _ -> decode.failure(Active, "MembershipStatus")
      }
    }),
  )
  decode.success(Member(
    organization_id:,
    user_id:,
    name:,
    email:,
    role:,
    status:,
  ))
}

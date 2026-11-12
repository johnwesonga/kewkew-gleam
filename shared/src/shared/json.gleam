//// JSON codecs for the shared domain types.
////
//// Object keys use the Gleam record field names (snake_case). Optional fields
//// are encoded as JSON null and are expected to be present when decoding.

import gleam/dynamic/decode
import gleam/json.{type Json}
import shared.{
  type EventActor, type IdentityPolicy, type InvitationDeliveryState,
  type Location, type Membership, type MembershipAuditEvent,
  type MembershipChangeType, type MembershipRole, type MembershipStatus,
  type Organization, type Queue, type QueueSchedule, type QueueSession,
  type QueueSessionEvent, type QueueSessionState, type ScheduleOccurrenceStatus,
  type Service, type StaffInvitation, type Ticket, type TicketEvent,
  type TicketStatus, type User, Active, Admin, Anonymous, Called, Cancelled,
  Closed, Completed, Failed, InvitationAccepted, Location, LocationAccessChanged,
  MemberReactivated, MemberSuspended, Membership, MembershipAuditEvent,
  MembershipCreated, NameRequired, NoShow, OccurrenceActive, OccurrenceBlocked,
  Open, Operator, Organization, Paused, Queue, QueueSchedule, QueueSession,
  QueueSessionEvent, RoleChanged, Sent, Service, Serving, Staff, StaffInvitation,
  Suspended, System, Ticket, TicketEvent, User, Visitor, Waiting,
}

// Enum codecs use stable API strings rather than constructor names.

pub fn membership_role_to_json(value: MembershipRole) -> Json {
  json.string(case value {
    Admin -> "admin"
    Operator -> "operator"
  })
}

pub fn membership_status_to_json(value: MembershipStatus) -> Json {
  json.string(case value {
    Active -> "active"
    Suspended -> "suspended"
  })
}

pub fn identity_policy_to_json(value: IdentityPolicy) -> Json {
  json.string(case value {
    Anonymous -> "anonymous"
    NameRequired -> "name_required"
  })
}

pub fn queue_session_state_to_json(value: QueueSessionState) -> Json {
  json.string(case value {
    Open -> "open"
    Paused -> "paused"
    Closed -> "closed"
  })
}

pub fn occurrence_status_to_json(value: ScheduleOccurrenceStatus) -> Json {
  json.string(case value {
    OccurrenceActive -> "active"
    OccurrenceBlocked -> "blocked"
  })
}

pub fn ticket_status_to_json(value: TicketStatus) -> Json {
  json.string(case value {
    Waiting -> "waiting"
    Called -> "called"
    Serving -> "serving"
    Completed -> "completed"
    Cancelled -> "cancelled"
    NoShow -> "no_show"
  })
}

pub fn event_actor_to_json(value: EventActor) -> Json {
  json.string(case value {
    Visitor -> "visitor"
    Staff -> "staff"
    System -> "system"
  })
}

pub fn invitation_delivery_state_to_json(
  value: InvitationDeliveryState,
) -> Json {
  json.string(case value {
    Sent -> "sent"
    Failed -> "failed"
  })
}

pub fn membership_change_type_to_json(value: MembershipChangeType) -> Json {
  json.string(case value {
    MembershipCreated -> "membership_created"
    RoleChanged -> "role_changed"
    LocationAccessChanged -> "location_access_changed"
    MemberSuspended -> "suspended"
    MemberReactivated -> "reactivated"
    InvitationAccepted -> "invitation_accepted"
  })
}

pub fn organization_to_json(value: Organization) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("name", json.string(value.name)),
    #("created_at", json.string(value.created_at)),
    #("updated_at", json.string(value.updated_at)),
  ])
}

pub fn user_to_json(value: User) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("name", json.string(value.name)),
    #("email", json.string(value.email)),
    #("image", json.nullable(value.image, json.string)),
  ])
}

pub fn membership_to_json(value: Membership) -> Json {
  json.object([
    #("organization_id", json.string(value.organization_id)),
    #("user_id", json.string(value.user_id)),
    #("role", membership_role_to_json(value.role)),
    #("status", membership_status_to_json(value.status)),
    #("location_ids", json.array(value.location_ids, json.string)),
    #("created_at", json.string(value.created_at)),
    #("updated_at", json.string(value.updated_at)),
  ])
}

pub fn location_to_json(value: Location) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("organization_id", json.string(value.organization_id)),
    #("name", json.string(value.name)),
    #("timezone", json.string(value.timezone)),
    #("is_active", json.bool(value.is_active)),
    #("created_at", json.string(value.created_at)),
    #("updated_at", json.string(value.updated_at)),
  ])
}

pub fn service_to_json(value: Service) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("organization_id", json.string(value.organization_id)),
    #("location_id", json.string(value.location_id)),
    #("name", json.string(value.name)),
    #("description", json.nullable(value.description, json.string)),
    #("is_active", json.bool(value.is_active)),
    #("created_at", json.string(value.created_at)),
    #("updated_at", json.string(value.updated_at)),
  ])
}

pub fn queue_to_json(value: Queue) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("organization_id", json.string(value.organization_id)),
    #("location_id", json.string(value.location_id)),
    #("service_id", json.string(value.service_id)),
    #("name", json.string(value.name)),
    #("identity_policy", identity_policy_to_json(value.identity_policy)),
    #(
      "active_ticket_capacity",
      json.nullable(value.active_ticket_capacity, json.int),
    ),
    #("is_active", json.bool(value.is_active)),
    #("public_id", json.nullable(value.public_id, json.string)),
    #("created_at", json.string(value.created_at)),
    #("updated_at", json.string(value.updated_at)),
  ])
}

pub fn queue_session_to_json(value: QueueSession) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("organization_id", json.string(value.organization_id)),
    #("queue_id", json.string(value.queue_id)),
    #("state", queue_session_state_to_json(value.state)),
    #("opened_at", json.string(value.opened_at)),
    #("closed_at", json.nullable(value.closed_at, json.string)),
    #("schedule_id", json.nullable(value.schedule_id, json.string)),
    #("schedule_version", json.nullable(value.schedule_version, json.int)),
    #("occurrence_key", json.nullable(value.occurrence_key, json.string)),
    #("signup_opens_at", json.nullable(value.signup_opens_at, json.string)),
    #(
      "scheduled_service_start_at",
      json.nullable(value.scheduled_service_start_at, json.string),
    ),
    #(
      "occurrence_ticket_cap",
      json.nullable(value.occurrence_ticket_cap, json.int),
    ),
    #("occurrence_status", occurrence_status_to_json(value.occurrence_status)),
  ])
}

pub fn ticket_to_json(value: Ticket) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("organization_id", json.string(value.organization_id)),
    #("queue_id", json.string(value.queue_id)),
    #("queue_session_id", json.string(value.queue_session_id)),
    #("ticket_number", json.int(value.ticket_number)),
    #("queue_sequence", json.int(value.queue_sequence)),
    #("status", ticket_status_to_json(value.status)),
    #("first_name", json.nullable(value.first_name, json.string)),
    #("last_name", json.nullable(value.last_name, json.string)),
    #("identity_policy", identity_policy_to_json(value.identity_policy)),
    #("joined_at", json.string(value.joined_at)),
    #("called_at", json.nullable(value.called_at, json.string)),
    #("started_at", json.nullable(value.started_at, json.string)),
    #("completed_at", json.nullable(value.completed_at, json.string)),
    #("cancelled_at", json.nullable(value.cancelled_at, json.string)),
    #("created_at", json.string(value.created_at)),
    #("updated_at", json.string(value.updated_at)),
  ])
}

pub fn ticket_event_to_json(value: TicketEvent) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("ticket_id", json.string(value.ticket_id)),
    #("from_status", json.nullable(value.from_status, ticket_status_to_json)),
    #("to_status", ticket_status_to_json(value.to_status)),
    #("actor_type", event_actor_to_json(value.actor_type)),
    #("actor_id", json.nullable(value.actor_id, json.string)),
    #("occurred_at", json.string(value.occurred_at)),
    #("metadata", json.nullable(value.metadata, json.string)),
  ])
}

pub fn queue_session_event_to_json(value: QueueSessionEvent) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("queue_id", json.string(value.queue_id)),
    #("session_id", json.string(value.session_id)),
    #("from_state", queue_session_state_to_json(value.from_state)),
    #("to_state", queue_session_state_to_json(value.to_state)),
    #("actor_user_id", json.string(value.actor_user_id)),
    #("occurred_at", json.string(value.occurred_at)),
  ])
}

pub fn queue_schedule_to_json(value: QueueSchedule) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("organization_id", json.string(value.organization_id)),
    #("queue_id", json.string(value.queue_id)),
    #("enabled", json.bool(value.enabled)),
    #("weekdays", json.array(value.weekdays, json.int)),
    #("signup_open_time", json.string(value.signup_open_time)),
    #("service_start_time", json.string(value.service_start_time)),
    #(
      "occurrence_ticket_cap",
      json.nullable(value.occurrence_ticket_cap, json.int),
    ),
    #("version", json.int(value.version)),
    #("updated_at", json.string(value.updated_at)),
  ])
}

pub fn staff_invitation_to_json(value: StaffInvitation) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("organization_id", json.string(value.organization_id)),
    #("invited_email", json.string(value.invited_email)),
    #("role", membership_role_to_json(value.role)),
    #("location_ids", json.array(value.location_ids, json.string)),
    #("created_by_user_id", json.string(value.created_by_user_id)),
    #("created_at", json.string(value.created_at)),
    #("expires_at", json.string(value.expires_at)),
    #("delivery_state", invitation_delivery_state_to_json(value.delivery_state)),
    #(
      "accepted_by_user_id",
      json.nullable(value.accepted_by_user_id, json.string),
    ),
    #("accepted_at", json.nullable(value.accepted_at, json.string)),
    #("revoked_at", json.nullable(value.revoked_at, json.string)),
  ])
}

pub fn membership_audit_event_to_json(value: MembershipAuditEvent) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("organization_id", json.string(value.organization_id)),
    #("actor_user_id", json.string(value.actor_user_id)),
    #("subject_user_id", json.string(value.subject_user_id)),
    #("change_type", membership_change_type_to_json(value.change_type)),
    #("before_role", json.nullable(value.before_role, membership_role_to_json)),
    #("after_role", json.nullable(value.after_role, membership_role_to_json)),
    #(
      "before_status",
      json.nullable(value.before_status, membership_status_to_json),
    ),
    #(
      "after_status",
      json.nullable(value.after_status, membership_status_to_json),
    ),
    #("details_json", json.nullable(value.details_json, json.string)),
    #("created_at", json.string(value.created_at)),
  ])
}

// Enum decoders reject unknown values so API/schema drift is visible to callers.

pub fn membership_role_decoder() -> decode.Decoder(MembershipRole) {
  decode.then(decode.string, fn(value) {
    case value {
      "admin" -> decode.success(Admin)
      "operator" -> decode.success(Operator)
      _ -> decode.failure(Admin, "membership role")
    }
  })
}

pub fn membership_status_decoder() -> decode.Decoder(MembershipStatus) {
  decode.then(decode.string, fn(value) {
    case value {
      "active" -> decode.success(Active)
      "suspended" -> decode.success(Suspended)
      _ -> decode.failure(Active, "membership status")
    }
  })
}

pub fn identity_policy_decoder() -> decode.Decoder(IdentityPolicy) {
  decode.then(decode.string, fn(value) {
    case value {
      "anonymous" -> decode.success(Anonymous)
      "name_required" -> decode.success(NameRequired)
      _ -> decode.failure(Anonymous, "identity policy")
    }
  })
}

pub fn queue_session_state_decoder() -> decode.Decoder(QueueSessionState) {
  decode.then(decode.string, fn(value) {
    case value {
      "open" -> decode.success(Open)
      "paused" -> decode.success(Paused)
      "closed" -> decode.success(Closed)
      _ -> decode.failure(Open, "queue session state")
    }
  })
}

pub fn occurrence_status_decoder() -> decode.Decoder(ScheduleOccurrenceStatus) {
  decode.then(decode.string, fn(value) {
    case value {
      "active" -> decode.success(OccurrenceActive)
      "blocked" -> decode.success(OccurrenceBlocked)
      _ -> decode.failure(OccurrenceActive, "schedule occurrence status")
    }
  })
}

pub fn ticket_status_decoder() -> decode.Decoder(TicketStatus) {
  decode.then(decode.string, fn(value) {
    case value {
      "waiting" -> decode.success(Waiting)
      "called" -> decode.success(Called)
      "serving" -> decode.success(Serving)
      "completed" -> decode.success(Completed)
      "cancelled" -> decode.success(Cancelled)
      "no_show" -> decode.success(NoShow)
      _ -> decode.failure(Waiting, "ticket status")
    }
  })
}

pub fn event_actor_decoder() -> decode.Decoder(EventActor) {
  decode.then(decode.string, fn(value) {
    case value {
      "visitor" -> decode.success(Visitor)
      "staff" -> decode.success(Staff)
      "system" -> decode.success(System)
      _ -> decode.failure(Visitor, "event actor")
    }
  })
}

pub fn invitation_delivery_state_decoder() -> decode.Decoder(
  InvitationDeliveryState,
) {
  decode.then(decode.string, fn(value) {
    case value {
      "sent" -> decode.success(Sent)
      "failed" -> decode.success(Failed)
      _ -> decode.failure(Sent, "invitation delivery state")
    }
  })
}

pub fn membership_change_type_decoder() -> decode.Decoder(MembershipChangeType) {
  decode.then(decode.string, fn(value) {
    case value {
      "membership_created" -> decode.success(MembershipCreated)
      "role_changed" -> decode.success(RoleChanged)
      "location_access_changed" -> decode.success(LocationAccessChanged)
      "suspended" -> decode.success(MemberSuspended)
      "reactivated" -> decode.success(MemberReactivated)
      "invitation_accepted" -> decode.success(InvitationAccepted)
      _ -> decode.failure(MembershipCreated, "membership change type")
    }
  })
}

pub fn organization_decoder() -> decode.Decoder(Organization) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use updated_at <- decode.field("updated_at", decode.string)
  decode.success(Organization(id:, name:, created_at:, updated_at:))
}

pub fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use email <- decode.field("email", decode.string)
  use image <- decode.field("image", decode.optional(decode.string))
  decode.success(User(id:, name:, email:, image:))
}

pub fn membership_decoder() -> decode.Decoder(Membership) {
  use organization_id <- decode.field("organization_id", decode.string)
  use user_id <- decode.field("user_id", decode.string)
  use role <- decode.field("role", membership_role_decoder())
  use status <- decode.field("status", membership_status_decoder())
  use location_ids <- decode.field("location_ids", decode.list(decode.string))
  use created_at <- decode.field("created_at", decode.string)
  use updated_at <- decode.field("updated_at", decode.string)
  decode.success(Membership(
    organization_id:,
    user_id:,
    role:,
    status:,
    location_ids:,
    created_at:,
    updated_at:,
  ))
}

pub fn location_decoder() -> decode.Decoder(Location) {
  use id <- decode.field("id", decode.string)
  use organization_id <- decode.field("organization_id", decode.string)
  use name <- decode.field("name", decode.string)
  use timezone <- decode.field("timezone", decode.string)
  use is_active <- decode.field("is_active", decode.bool)
  use created_at <- decode.field("created_at", decode.string)
  use updated_at <- decode.field("updated_at", decode.string)
  decode.success(Location(
    id:,
    organization_id:,
    name:,
    timezone:,
    is_active:,
    created_at:,
    updated_at:,
  ))
}

pub fn service_decoder() -> decode.Decoder(Service) {
  use id <- decode.field("id", decode.string)
  use organization_id <- decode.field("organization_id", decode.string)
  use location_id <- decode.field("location_id", decode.string)
  use name <- decode.field("name", decode.string)
  use description <- decode.field("description", decode.optional(decode.string))
  use is_active <- decode.field("is_active", decode.bool)
  use created_at <- decode.field("created_at", decode.string)
  use updated_at <- decode.field("updated_at", decode.string)
  decode.success(Service(
    id:,
    organization_id:,
    location_id:,
    name:,
    description:,
    is_active:,
    created_at:,
    updated_at:,
  ))
}

pub fn queue_decoder() -> decode.Decoder(Queue) {
  use id <- decode.field("id", decode.string)
  use organization_id <- decode.field("organization_id", decode.string)
  use location_id <- decode.field("location_id", decode.string)
  use service_id <- decode.field("service_id", decode.string)
  use name <- decode.field("name", decode.string)
  use identity_policy <- decode.field(
    "identity_policy",
    identity_policy_decoder(),
  )
  use active_ticket_capacity <- decode.field(
    "active_ticket_capacity",
    decode.optional(decode.int),
  )
  use is_active <- decode.field("is_active", decode.bool)
  use public_id <- decode.field("public_id", decode.optional(decode.string))
  use created_at <- decode.field("created_at", decode.string)
  use updated_at <- decode.field("updated_at", decode.string)
  decode.success(Queue(
    id:,
    organization_id:,
    location_id:,
    service_id:,
    name:,
    identity_policy:,
    active_ticket_capacity:,
    is_active:,
    public_id:,
    created_at:,
    updated_at:,
  ))
}

pub fn queue_session_decoder() -> decode.Decoder(QueueSession) {
  use id <- decode.field("id", decode.string)
  use organization_id <- decode.field("organization_id", decode.string)
  use queue_id <- decode.field("queue_id", decode.string)
  use state <- decode.field("state", queue_session_state_decoder())
  use opened_at <- decode.field("opened_at", decode.string)
  use closed_at <- decode.field("closed_at", decode.optional(decode.string))
  use schedule_id <- decode.field("schedule_id", decode.optional(decode.string))
  use schedule_version <- decode.field(
    "schedule_version",
    decode.optional(decode.int),
  )
  use occurrence_key <- decode.field(
    "occurrence_key",
    decode.optional(decode.string),
  )
  use signup_opens_at <- decode.field(
    "signup_opens_at",
    decode.optional(decode.string),
  )
  use scheduled_service_start_at <- decode.field(
    "scheduled_service_start_at",
    decode.optional(decode.string),
  )
  use occurrence_ticket_cap <- decode.field(
    "occurrence_ticket_cap",
    decode.optional(decode.int),
  )
  use occurrence_status <- decode.field(
    "occurrence_status",
    occurrence_status_decoder(),
  )
  decode.success(QueueSession(
    id:,
    organization_id:,
    queue_id:,
    state:,
    opened_at:,
    closed_at:,
    schedule_id:,
    schedule_version:,
    occurrence_key:,
    signup_opens_at:,
    scheduled_service_start_at:,
    occurrence_ticket_cap:,
    occurrence_status:,
  ))
}

pub fn ticket_decoder() -> decode.Decoder(Ticket) {
  use id <- decode.field("id", decode.string)
  use organization_id <- decode.field("organization_id", decode.string)
  use queue_id <- decode.field("queue_id", decode.string)
  use queue_session_id <- decode.field("queue_session_id", decode.string)
  use ticket_number <- decode.field("ticket_number", decode.int)
  use queue_sequence <- decode.field("queue_sequence", decode.int)
  use status <- decode.field("status", ticket_status_decoder())
  use first_name <- decode.field("first_name", decode.optional(decode.string))
  use last_name <- decode.field("last_name", decode.optional(decode.string))
  use identity_policy <- decode.field(
    "identity_policy",
    identity_policy_decoder(),
  )
  use joined_at <- decode.field("joined_at", decode.string)
  use called_at <- decode.field("called_at", decode.optional(decode.string))
  use started_at <- decode.field("started_at", decode.optional(decode.string))
  use completed_at <- decode.field(
    "completed_at",
    decode.optional(decode.string),
  )
  use cancelled_at <- decode.field(
    "cancelled_at",
    decode.optional(decode.string),
  )
  use created_at <- decode.field("created_at", decode.string)
  use updated_at <- decode.field("updated_at", decode.string)
  decode.success(Ticket(
    id:,
    organization_id:,
    queue_id:,
    queue_session_id:,
    ticket_number:,
    queue_sequence:,
    status:,
    first_name:,
    last_name:,
    identity_policy:,
    joined_at:,
    called_at:,
    started_at:,
    completed_at:,
    cancelled_at:,
    created_at:,
    updated_at:,
  ))
}

pub fn ticket_event_decoder() -> decode.Decoder(TicketEvent) {
  use id <- decode.field("id", decode.string)
  use ticket_id <- decode.field("ticket_id", decode.string)
  use from_status <- decode.field(
    "from_status",
    decode.optional(ticket_status_decoder()),
  )
  use to_status <- decode.field("to_status", ticket_status_decoder())
  use actor_type <- decode.field("actor_type", event_actor_decoder())
  use actor_id <- decode.field("actor_id", decode.optional(decode.string))
  use occurred_at <- decode.field("occurred_at", decode.string)
  use metadata <- decode.field("metadata", decode.optional(decode.string))
  decode.success(TicketEvent(
    id:,
    ticket_id:,
    from_status:,
    to_status:,
    actor_type:,
    actor_id:,
    occurred_at:,
    metadata:,
  ))
}

pub fn queue_session_event_decoder() -> decode.Decoder(QueueSessionEvent) {
  use id <- decode.field("id", decode.string)
  use queue_id <- decode.field("queue_id", decode.string)
  use session_id <- decode.field("session_id", decode.string)
  use from_state <- decode.field("from_state", queue_session_state_decoder())
  use to_state <- decode.field("to_state", queue_session_state_decoder())
  use actor_user_id <- decode.field("actor_user_id", decode.string)
  use occurred_at <- decode.field("occurred_at", decode.string)
  decode.success(QueueSessionEvent(
    id:,
    queue_id:,
    session_id:,
    from_state:,
    to_state:,
    actor_user_id:,
    occurred_at:,
  ))
}

pub fn queue_schedule_decoder() -> decode.Decoder(QueueSchedule) {
  use id <- decode.field("id", decode.string)
  use organization_id <- decode.field("organization_id", decode.string)
  use queue_id <- decode.field("queue_id", decode.string)
  use enabled <- decode.field("enabled", decode.bool)
  use weekdays <- decode.field("weekdays", decode.list(decode.int))
  use signup_open_time <- decode.field("signup_open_time", decode.string)
  use service_start_time <- decode.field("service_start_time", decode.string)
  use occurrence_ticket_cap <- decode.field(
    "occurrence_ticket_cap",
    decode.optional(decode.int),
  )
  use version <- decode.field("version", decode.int)
  use updated_at <- decode.field("updated_at", decode.string)
  decode.success(QueueSchedule(
    id:,
    organization_id:,
    queue_id:,
    enabled:,
    weekdays:,
    signup_open_time:,
    service_start_time:,
    occurrence_ticket_cap:,
    version:,
    updated_at:,
  ))
}

pub fn staff_invitation_decoder() -> decode.Decoder(StaffInvitation) {
  use id <- decode.field("id", decode.string)
  use organization_id <- decode.field("organization_id", decode.string)
  use invited_email <- decode.field("invited_email", decode.string)
  use role <- decode.field("role", membership_role_decoder())
  use location_ids <- decode.field("location_ids", decode.list(decode.string))
  use created_by_user_id <- decode.field("created_by_user_id", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use expires_at <- decode.field("expires_at", decode.string)
  use delivery_state <- decode.field(
    "delivery_state",
    invitation_delivery_state_decoder(),
  )
  use accepted_by_user_id <- decode.field(
    "accepted_by_user_id",
    decode.optional(decode.string),
  )
  use accepted_at <- decode.field("accepted_at", decode.optional(decode.string))
  use revoked_at <- decode.field("revoked_at", decode.optional(decode.string))
  decode.success(StaffInvitation(
    id:,
    organization_id:,
    invited_email:,
    role:,
    location_ids:,
    created_by_user_id:,
    created_at:,
    expires_at:,
    delivery_state:,
    accepted_by_user_id:,
    accepted_at:,
    revoked_at:,
  ))
}

pub fn membership_audit_event_decoder() -> decode.Decoder(MembershipAuditEvent) {
  use id <- decode.field("id", decode.string)
  use organization_id <- decode.field("organization_id", decode.string)
  use actor_user_id <- decode.field("actor_user_id", decode.string)
  use subject_user_id <- decode.field("subject_user_id", decode.string)
  use change_type <- decode.field(
    "change_type",
    membership_change_type_decoder(),
  )
  use before_role <- decode.field(
    "before_role",
    decode.optional(membership_role_decoder()),
  )
  use after_role <- decode.field(
    "after_role",
    decode.optional(membership_role_decoder()),
  )
  use before_status <- decode.field(
    "before_status",
    decode.optional(membership_status_decoder()),
  )
  use after_status <- decode.field(
    "after_status",
    decode.optional(membership_status_decoder()),
  )
  use details_json <- decode.field(
    "details_json",
    decode.optional(decode.string),
  )
  use created_at <- decode.field("created_at", decode.string)
  decode.success(MembershipAuditEvent(
    id:,
    organization_id:,
    actor_user_id:,
    subject_user_id:,
    change_type:,
    before_role:,
    after_role:,
    before_status:,
    after_status:,
    details_json:,
    created_at:,
  ))
}

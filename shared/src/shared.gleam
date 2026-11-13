import gleam/option.{type Option}

/// Organization-level business data shared by the browser client and server.
/// Timestamps use ISO 8601 strings so the package can be compiled to both
/// JavaScript and Erlang without choosing a runtime-specific date library.
pub type Organization {
  Organization(id: String, name: String, created_at: String, updated_at: String)
}

/// Public profile fields only. Authentication secrets and account credentials
/// remain server-side.
pub type User {
  User(id: String, name: String, email: String, image: Option(String))
}

pub type MembershipRole {
  Admin
  Operator
}

pub type MembershipStatus {
  Active
  Suspended
}

/// Location access is represented as a list because the database stores it in
/// the membership_location_access join table.
pub type Membership {
  Membership(
    organization_id: String,
    user_id: String,
    role: MembershipRole,
    status: MembershipStatus,
    location_ids: List(String),
    created_at: String,
    updated_at: String,
  )
}

pub type Location {
  Location(
    id: String,
    organization_id: String,
    name: String,
    timezone: String,
    is_active: Bool,
    created_at: String,
    updated_at: String,
  )
}

pub type Service {
  Service(
    id: String,
    organization_id: String,
    location_id: String,
    name: String,
    description: Option(String),
    is_active: Bool,
    created_at: String,
    updated_at: String,
  )
}

pub type IdentityPolicy {
  Anonymous
  NameRequired
}

pub type Queue {
  Queue(
    id: String,
    organization_id: String,
    location_id: String,
    service_id: String,
    name: String,
    identity_policy: IdentityPolicy,
    active_ticket_capacity: Option(Int),
    is_active: Bool,
    current_session_state: Option(QueueSessionState),
    public_id: Option(String),
    created_at: String,
    updated_at: String,
  )
}

/// The role-aware organization data returned to an authenticated staff client.
pub type OrganizationOverview {
  OrganizationOverview(
    organization: Organization,
    role: MembershipRole,
    can_manage: Bool,
    locations: List(LocationOverview),
  )
}

pub type LocationOverview {
  LocationOverview(location: Location, services: List(ServiceOverview))
}

pub type ServiceOverview {
  ServiceOverview(service: Service, queues: List(Queue))
}

pub type QueueSessionState {
  Open
  Paused
  Closed
}

pub type ScheduleOccurrenceStatus {
  OccurrenceActive
  OccurrenceBlocked
}

pub type QueueSession {
  QueueSession(
    id: String,
    organization_id: String,
    queue_id: String,
    state: QueueSessionState,
    opened_at: String,
    closed_at: Option(String),
    schedule_id: Option(String),
    schedule_version: Option(Int),
    occurrence_key: Option(String),
    signup_opens_at: Option(String),
    scheduled_service_start_at: Option(String),
    occurrence_ticket_cap: Option(Int),
    occurrence_status: ScheduleOccurrenceStatus,
  )
}

pub type TicketStatus {
  Waiting
  Called
  Serving
  Completed
  Cancelled
  NoShow
}

pub type Ticket {
  Ticket(
    id: String,
    organization_id: String,
    queue_id: String,
    queue_session_id: String,
    ticket_number: Int,
    queue_sequence: Int,
    status: TicketStatus,
    first_name: Option(String),
    last_name: Option(String),
    identity_policy: IdentityPolicy,
    joined_at: String,
    called_at: Option(String),
    started_at: Option(String),
    completed_at: Option(String),
    cancelled_at: Option(String),
    created_at: String,
    updated_at: String,
  )
}

pub type EventActor {
  Visitor
  Staff
  System
}

pub type TicketEvent {
  TicketEvent(
    id: String,
    ticket_id: String,
    from_status: Option(TicketStatus),
    to_status: TicketStatus,
    actor_type: EventActor,
    actor_id: Option(String),
    occurred_at: String,
    metadata: Option(String),
  )
}

pub type QueueSessionEvent {
  QueueSessionEvent(
    id: String,
    queue_id: String,
    session_id: String,
    from_state: QueueSessionState,
    to_state: QueueSessionState,
    actor_user_id: String,
    occurred_at: String,
  )
}

pub type QueueSchedule {
  QueueSchedule(
    id: String,
    organization_id: String,
    queue_id: String,
    enabled: Bool,
    weekdays: List(Int),
    signup_open_time: String,
    service_start_time: String,
    occurrence_ticket_cap: Option(Int),
    version: Int,
    updated_at: String,
  )
}

pub type InvitationDeliveryState {
  Sent
  Failed
}

/// An invitation view without its token digest or invitation token.
pub type StaffInvitation {
  StaffInvitation(
    id: String,
    organization_id: String,
    invited_email: String,
    role: MembershipRole,
    location_ids: List(String),
    created_by_user_id: String,
    created_at: String,
    expires_at: String,
    delivery_state: InvitationDeliveryState,
    accepted_by_user_id: Option(String),
    accepted_at: Option(String),
    revoked_at: Option(String),
  )
}

pub type MembershipChangeType {
  MembershipCreated
  RoleChanged
  LocationAccessChanged
  MemberSuspended
  MemberReactivated
  InvitationAccepted
}

pub type MembershipAuditEvent {
  MembershipAuditEvent(
    id: String,
    organization_id: String,
    actor_user_id: String,
    subject_user_id: String,
    change_type: MembershipChangeType,
    before_role: Option(MembershipRole),
    after_role: Option(MembershipRole),
    before_status: Option(MembershipStatus),
    after_status: Option(MembershipStatus),
    details_json: Option(String),
    created_at: String,
  )
}

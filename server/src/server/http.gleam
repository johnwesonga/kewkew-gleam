import gleam/dynamic/decode
import gleam/http
import gleam/http/cookie
import gleam/http/request as http_request
import gleam/http/response
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import server/authentication
import server/email/resend
import server/http/requests as http_requests
import server/organization/invitations
import server/organization/locations
import server/organization/overview
import server/organization/profile
import server/organization/queues
import server/organization/services
import server/visitor/queue
import server/visitor/tickets as visitor_tickets
import sqlight
import wisp

const max_sign_in_body_bytes = 16_384

const max_invitation_body_bytes = 32_768

pub type Context {
  Context(
    database: sqlight.Connection,
    resend_api_key: String,
    resend_from: String,
    public_app_url: String,
  )
}

/// Handle the API routes currently implemented by the server.
pub fn handle(request: wisp.Request, context: Context) -> wisp.Response {
  use <- wisp.log_request(request)
  case request.path {
    "/api/auth/sign-in" ->
      case request.method {
        http.Post -> sign_in(request, context)
        _ -> wisp.method_not_allowed([http.Get, http.Post])
      }
    "/api/auth/sign-out" ->
      case request.method {
        http.Post -> sign_out(request, context)
        _ -> wisp.method_not_allowed([http.Post])
      }
    "/api/invitations/accept" ->
      case request.method {
        http.Post -> accept_invitation(request, context)
        _ -> wisp.method_not_allowed([http.Post])
      }
    "/api/invitations/accept-existing" ->
      case request.method {
        http.Post -> accept_existing_invitation(request, context)
        _ -> wisp.method_not_allowed([http.Post])
      }
    "/api/organizations" ->
      case request.method {
        http.Get -> list_organizations(request, context)
        _ -> wisp.method_not_allowed([http.Get])
      }
    "/health" ->
      case request.method {
        http.Get -> json_response(200, "{\"status\":\"ok\"}")
        _ -> wisp.method_not_allowed([http.Get])
      }
    _ ->
      case string.split(request.path, "/") {
        ["", "api", "public", "queues", _, "tickets"] ->
          case request.method {
            http.Post -> join_anonymous_ticket(request, context)
            _ -> wisp.method_not_allowed([http.Post])
          }
        ["", "api", "public", "tickets", _] ->
          case request.method {
            http.Get -> track_public_ticket(request, context)
            http.Delete -> cancel_public_ticket(request, context)
            _ -> wisp.method_not_allowed([http.Get, http.Delete])
          }
        ["", "api", "public", "queues", _] ->
          case request.method {
            http.Get -> public_queue(request, context)
            _ -> wisp.method_not_allowed([http.Get])
          }
        ["", "api", "public", "locations", _] ->
          case request.method {
            http.Get -> public_location(request, context)
            _ -> wisp.method_not_allowed([http.Get])
          }
        _ -> organization_resource(request, context)
      }
  }
}

fn cancel_public_ticket(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
  case string.split(request.path, "/") {
    ["", "api", "public", "tickets", token] ->
      case visitor_tickets.cancel(context.database, token) {
        Ok(details) -> json_response(200, details)
        Error(visitor_tickets.CancellationNotAllowed) ->
          json_response(
            409,
            error_json(
              "tickets can only be cancelled while waiting; please ask staff for help",
            ),
          )
        Error(visitor_tickets.QueueUnavailable)
        | Error(visitor_tickets.InvalidJoinAttempt) ->
          json_response(404, error_json("ticket unavailable"))
        Error(visitor_tickets.DatabaseFailure(_)) ->
          json_response(
            500,
            error_json("ticket cancellation could not be completed"),
          )
        Error(_) ->
          json_response(
            500,
            error_json("ticket cancellation could not be completed"),
          )
      }
    _ -> json_response(404, error_json("ticket unavailable"))
  }
}

fn join_anonymous_ticket(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
  case string.split(request.path, "/") {
    ["", "api", "public", "queues", public_id, "tickets"] ->
      request
      |> wisp.set_max_body_size(max_sign_in_body_bytes)
      |> wisp.require_bit_array_body(fn(body) {
        case http_requests.visitor_join(body) {
          Error(_) -> json_response(400, error_json("invalid join attempt"))
          Ok(#(join_attempt_token, first_name, last_name)) ->
            case
              visitor_tickets.join_visitor(
                context.database,
                public_id,
                join_attempt_token,
                first_name,
                last_name,
              )
            {
              Ok(details) -> json_response(201, details)
              Error(visitor_tickets.InvalidJoinAttempt) ->
                json_response(400, error_json("invalid join attempt"))
              Error(visitor_tickets.QueueUnavailable) ->
                json_response(
                  409,
                  error_json("this queue is not accepting visitors now"),
                )
              Error(visitor_tickets.FirstNameRequired) ->
                json_response(400, error_json("first name is required"))
              Error(visitor_tickets.LastNameRequired) ->
                json_response(400, error_json("last name is required"))
              Error(visitor_tickets.QueueFull) ->
                json_response(409, error_json("this queue is full"))
              Error(visitor_tickets.CancellationNotAllowed) ->
                json_response(
                  409,
                  error_json("this ticket cannot be cancelled"),
                )
              Error(visitor_tickets.DatabaseFailure(_)) ->
                json_response(
                  500,
                  error_json("your queue request could not be completed"),
                )
            }
        }
      })
    _ -> json_response(404, error_json("queue unavailable"))
  }
}

fn track_public_ticket(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
  case string.split(request.path, "/") {
    ["", "api", "public", "tickets", token] ->
      case visitor_tickets.track(context.database, token) {
        Ok(details) -> json_response(200, details)
        Error(visitor_tickets.QueueUnavailable) ->
          json_response(404, error_json("ticket unavailable"))
        Error(visitor_tickets.InvalidJoinAttempt) ->
          json_response(404, error_json("ticket unavailable"))
        Error(_) -> json_response(500, error_json("ticket unavailable"))
      }
    _ -> json_response(404, error_json("ticket unavailable"))
  }
}

fn public_location(request: wisp.Request, context: Context) -> wisp.Response {
  case string.split(request.path, "/") {
    ["", "api", "public", "locations", location_id] ->
      case queue.location_services(context.database, location_id) {
        Ok(details) -> json_response(200, details)
        Error(queue.NotFound) ->
          json_response(404, error_json("location unavailable"))
        Error(queue.DatabaseFailure(_)) ->
          json_response(500, error_json("location unavailable"))
      }
    _ -> json_response(404, error_json("location unavailable"))
  }
}

fn public_queue(request: wisp.Request, context: Context) -> wisp.Response {
  case string.split(request.path, "/") {
    ["", "api", "public", "queues", public_id] ->
      case queue.lookup(context.database, public_id) {
        Ok(details) -> json_response(200, details)
        Error(queue.NotFound) ->
          json_response(404, error_json("queue unavailable"))
        Error(queue.DatabaseFailure(_)) ->
          json_response(500, error_json("queue unavailable"))
      }
    _ -> json_response(404, error_json("queue unavailable"))
  }
}

fn organization_resource(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
  case string.split(request.path, "/") {
    ["", "api", "organizations", organization_id, "locations"] ->
      case request.method {
        http.Post -> create_location(request, context, organization_id)
        _ -> wisp.method_not_allowed([http.Post])
      }
    ["", "api", "organizations", organization_id, "staff", "invitations"] ->
      case request.method {
        http.Post -> create_invitation(request, context, organization_id)
        http.Get -> list_staff_invitations(request, context, organization_id)
        _ -> wisp.method_not_allowed([http.Get, http.Post])
      }
    ["", "api", "organizations", organization_id, "locations", location_id] ->
      case request.method {
        http.Put ->
          update_location(request, context, organization_id, location_id)
        http.Patch ->
          set_location_active(request, context, organization_id, location_id)
        _ -> wisp.method_not_allowed([http.Put, http.Patch])
      }
    [
      "",
      "api",
      "organizations",
      organization_id,
      "locations",
      location_id,
      "services",
    ] ->
      case request.method {
        http.Post ->
          create_service(request, context, organization_id, location_id)
        _ -> wisp.method_not_allowed([http.Post])
      }
    [
      "",
      "api",
      "organizations",
      organization_id,
      "locations",
      location_id,
      "services",
      service_id,
      "queues",
      queue_id,
      "sessions",
    ] ->
      case request.method {
        http.Post ->
          open_queue_session(
            request,
            context,
            organization_id,
            location_id,
            service_id,
            queue_id,
          )
        _ -> wisp.method_not_allowed([http.Post])
      }
    [
      "",
      "api",
      "organizations",
      organization_id,
      "locations",
      location_id,
      "services",
      service_id,
    ] ->
      case request.method {
        http.Put ->
          update_service(
            request,
            context,
            organization_id,
            location_id,
            service_id,
          )
        http.Patch ->
          set_service_active(
            request,
            context,
            organization_id,
            location_id,
            service_id,
          )
        _ -> wisp.method_not_allowed([http.Put, http.Patch])
      }
    [
      "",
      "api",
      "organizations",
      organization_id,
      "locations",
      location_id,
      "services",
      service_id,
      "queues",
    ] ->
      case request.method {
        http.Post ->
          create_queue(
            request,
            context,
            organization_id,
            location_id,
            service_id,
          )
        _ -> wisp.method_not_allowed([http.Post])
      }
    [
      "",
      "api",
      "organizations",
      organization_id,
      "locations",
      location_id,
      "services",
      service_id,
      "queues",
      queue_id,
    ] ->
      case request.method {
        http.Put ->
          update_queue(
            request,
            context,
            organization_id,
            location_id,
            service_id,
            queue_id,
          )
        http.Patch ->
          set_queue_active(
            request,
            context,
            organization_id,
            location_id,
            service_id,
            queue_id,
          )
        _ -> wisp.method_not_allowed([http.Put, http.Patch])
      }
    _ -> organization_detail(request, context)
  }
}

fn create_invitation(
  request: wisp.Request,
  context: Context,
  organization_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_invitation_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.staff_invitation(body) {
      Error(_) -> json_response(400, error_json("invalid invitation"))
      Ok(#(email, role, location_ids)) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            invitations.create(
              context.database,
              user_id,
              organization_id,
              email,
              role,
              location_ids,
            )
          {
            Ok(invitation) -> {
              let acceptance_url =
                context.public_app_url
                <> "/invite/accept?token="
                <> invitation.token
              case context.resend_api_key, context.resend_from {
                "", _ | _, "" -> {
                  let _ =
                    invitations.set_delivery_state(
                      context.database,
                      invitation.id,
                      "failed",
                    )
                  json_response(
                    503,
                    error_json("invitation email delivery is not configured"),
                  )
                }
                api_key, from ->
                  case
                    resend.send_invitation(
                      api_key,
                      from,
                      invitation.email,
                      organization_name(context.database, organization_id),
                      invitation.role,
                      acceptance_url,
                      invitation.expires_at,
                    )
                  {
                    Ok(Nil) ->
                      case
                        invitations.set_delivery_state(
                          context.database,
                          invitation.id,
                          "sent",
                        )
                      {
                        Ok(Nil) -> invitation_created_response(invitation)
                        Error(_) ->
                          json_response(
                            500,
                            error_json(
                              "invitation delivery state could not be saved",
                            ),
                          )
                      }
                    Error(_) -> {
                      let _ =
                        invitations.set_delivery_state(
                          context.database,
                          invitation.id,
                          "failed",
                        )
                      json_response(
                        502,
                        error_json("invitation email could not be delivered"),
                      )
                    }
                  }
              }
            }
            Error(invitations.InvalidInvitation) ->
              json_response(
                400,
                error_json("choose a valid role and location access"),
              )
            Error(invitations.Forbidden) ->
              json_response(403, error_json("administrator access required"))
            Error(invitations.NotFound) ->
              json_response(404, error_json("not found"))
            Error(invitations.Conflict) ->
              json_response(
                409,
                error_json("an open invitation already exists for this email"),
              )
            Error(invitations.DatabaseFailure(_)) ->
              json_response(500, error_json("invitation could not be created"))
          }
        })
    }
  })
}

fn list_staff_invitations(
  request: wisp.Request,
  context: Context,
  organization_id: String,
) -> wisp.Response {
  with_authenticated_user(request, context, fn(user_id) {
    case invitations.list_sent(context.database, user_id, organization_id) {
      Ok(body) -> json_response(200, body)
      Error(invitations.Forbidden) ->
        json_response(403, error_json("administrator access required"))
      Error(invitations.NotFound) -> json_response(404, error_json("not found"))
      Error(_) ->
        json_response(500, error_json("invitations could not be loaded"))
    }
  })
}

fn invitation_created_response(
  invitation: invitations.InviteResult,
) -> wisp.Response {
  json_response(
    201,
    json.to_string(
      json.object([
        #("id", json.string(invitation.id)),
        #("email", json.string(invitation.email)),
        #("role", json.string(invitation.role)),
        #("expires_at", json.string(invitation.expires_at)),
        #("delivery_state", json.string("sent")),
        #("delivery_message", json.string("The invitation email was sent.")),
      ]),
    ),
  )
}

fn organization_name(
  connection: sqlight.Connection,
  organization_id: String,
) -> String {
  case
    sqlight.query(
      "SELECT name FROM organizations WHERE id = ?",
      on: connection,
      with: [sqlight.text(organization_id)],
      expecting: decode.list(decode.string),
    )
  {
    Ok([[name]]) -> name
    _ -> "your organization"
  }
}

fn accept_invitation(request: wisp.Request, context: Context) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_invitation_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.invitation_acceptance(body) {
      Error(_) ->
        json_response(400, error_json("invalid invitation acceptance"))
      Ok(#(token, name, password)) ->
        case invitations.accept(context.database, token, name, password) {
          Ok(Nil) -> json_response(200, "{\"status\":\"accepted\"}")
          Error(invitations.InvalidOrExpired) ->
            json_response(
              400,
              error_json("invitation is invalid, expired, or already used"),
            )
          Error(invitations.ExistingIdentityNeedsSignIn) ->
            json_response(
              409,
              error_json(
                "sign in to your existing account to accept this invitation",
              ),
            )
          Error(invitations.PasswordRejected) ->
            json_response(
              400,
              error_json("use a name and password of at least 12 characters"),
            )
          Error(invitations.AcceptDatabaseFailure(_)) ->
            json_response(500, error_json("invitation could not be accepted"))
        }
    }
  })
}

fn accept_existing_invitation(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_invitation_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.existing_invitation_acceptance(body) {
      Error(_) ->
        json_response(400, error_json("invalid invitation acceptance"))
      Ok(token) ->
        with_authenticated_user(request, context, fn(user_id) {
          case invitations.accept_for_user(context.database, token, user_id) {
            Ok(Nil) -> json_response(200, "{\"status\":\"accepted\"}")
            Error(invitations.InvalidOrExpired) ->
              json_response(
                400,
                error_json(
                  "invitation is invalid, expired, or does not match this account",
                ),
              )
            Error(invitations.ExistingIdentityNeedsSignIn) ->
              json_response(
                409,
                error_json(
                  "sign in to your existing account to accept this invitation",
                ),
              )
            Error(invitations.PasswordRejected) ->
              json_response(400, error_json("invalid invitation acceptance"))
            Error(invitations.AcceptDatabaseFailure(_)) ->
              json_response(500, error_json("invitation could not be accepted"))
          }
        })
    }
  })
}

fn set_location_active(
  request: wisp.Request,
  context: Context,
  organization_id: String,
  location_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case json.parse_bits(body, decode.bool) {
      Error(_) ->
        json_response(400, error_json("invalid location availability"))
      Ok(is_active) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            locations.set_active(
              context.database,
              user_id,
              organization_id,
              location_id,
              is_active,
            )
          {
            Ok(Nil) -> location_overview(context, user_id, organization_id)
            Error(error) -> location_error_response(error)
          }
        })
    }
  })
}

fn set_service_active(
  request: wisp.Request,
  context: Context,
  organization_id: String,
  location_id: String,
  service_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case json.parse_bits(body, decode.bool) {
      Error(_) -> json_response(400, error_json("invalid service availability"))
      Ok(is_active) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            services.set_active(
              context.database,
              user_id,
              organization_id,
              location_id,
              service_id,
              is_active,
            )
          {
            Ok(Nil) -> location_overview(context, user_id, organization_id)
            Error(error) -> service_error_response(error)
          }
        })
    }
  })
}

fn create_queue(
  request: wisp.Request,
  context: Context,
  organization_id: String,
  location_id: String,
  service_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.queue_details(body) {
      Error(_) -> json_response(400, error_json("invalid queue details"))
      Ok(#(name, identity_policy, capacity)) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            queues.create(
              context.database,
              user_id,
              organization_id,
              location_id,
              service_id,
              name,
              identity_policy,
              capacity,
            )
          {
            Ok(Nil) -> location_overview(context, user_id, organization_id)
            Error(error) -> queue_error_response(error)
          }
        })
    }
  })
}

fn update_queue(
  request: wisp.Request,
  context: Context,
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.queue_details(body) {
      Error(_) -> json_response(400, error_json("invalid queue details"))
      Ok(#(name, identity_policy, capacity)) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            queues.update(
              context.database,
              user_id,
              organization_id,
              location_id,
              service_id,
              queue_id,
              name,
              identity_policy,
              capacity,
            )
          {
            Ok(Nil) -> location_overview(context, user_id, organization_id)
            Error(error) -> queue_error_response(error)
          }
        })
    }
  })
}

fn set_queue_active(
  request: wisp.Request,
  context: Context,
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case json.parse_bits(body, decode.bool) {
      Error(_) -> json_response(400, error_json("invalid queue availability"))
      Ok(is_active) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            queues.set_active(
              context.database,
              user_id,
              organization_id,
              location_id,
              service_id,
              queue_id,
              is_active,
            )
          {
            Ok(Nil) -> location_overview(context, user_id, organization_id)
            Error(error) -> queue_error_response(error)
          }
        })
    }
  })
}

fn open_queue_session(
  request: wisp.Request,
  context: Context,
  organization_id: String,
  location_id: String,
  service_id: String,
  queue_id: String,
) -> wisp.Response {
  with_authenticated_user(request, context, fn(user_id) {
    case
      queues.open_session(
        context.database,
        user_id,
        organization_id,
        location_id,
        service_id,
        queue_id,
      )
    {
      Ok(Nil) -> location_overview(context, user_id, organization_id)
      Error(error) -> queue_error_response(error)
    }
  })
}

fn queue_error_response(error: queues.QueueError) -> wisp.Response {
  case error {
    queues.InvalidName ->
      json_response(400, error_json("queue name is required"))
    queues.InvalidIdentityPolicy ->
      json_response(400, error_json("invalid identity policy"))
    queues.InvalidCapacity ->
      json_response(400, error_json("capacity must be a positive integer"))
    queues.QueueInactive ->
      json_response(
        409,
        error_json("activate this queue before opening a session"),
      )
    queues.LocationInactive ->
      json_response(
        409,
        error_json("activate this location before opening a session"),
      )
    queues.ServiceInactive ->
      json_response(
        409,
        error_json("activate this service before opening a session"),
      )
    queues.SessionAlreadyOpen ->
      json_response(
        409,
        error_json("this queue already has an open or paused session"),
      )
    queues.Forbidden ->
      json_response(403, error_json("administrator access required"))
    queues.QueueAccessForbidden ->
      json_response(403, error_json("queue access required"))
    queues.NotFound -> json_response(404, error_json("not found"))
    queues.DatabaseFailure(_) ->
      json_response(500, error_json("request could not be completed"))
  }
}

fn create_service(
  request: wisp.Request,
  context: Context,
  organization_id: String,
  location_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.service_details(body) {
      Error(_) -> json_response(400, error_json("invalid service details"))
      Ok(#(name, description)) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            services.create(
              context.database,
              user_id,
              organization_id,
              location_id,
              name,
              description,
            )
          {
            Ok(Nil) -> location_overview(context, user_id, organization_id)
            Error(error) -> service_error_response(error)
          }
        })
    }
  })
}

fn update_service(
  request: wisp.Request,
  context: Context,
  organization_id: String,
  location_id: String,
  service_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.service_details(body) {
      Error(_) -> json_response(400, error_json("invalid service details"))
      Ok(#(name, description)) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            services.update(
              context.database,
              user_id,
              organization_id,
              location_id,
              service_id,
              name,
              description,
            )
          {
            Ok(Nil) -> location_overview(context, user_id, organization_id)
            Error(error) -> service_error_response(error)
          }
        })
    }
  })
}

fn service_error_response(error: services.ServiceError) -> wisp.Response {
  case error {
    services.InvalidName ->
      json_response(400, error_json("service name is required"))
    services.Forbidden ->
      json_response(403, error_json("administrator access required"))
    services.NotFound -> json_response(404, error_json("not found"))
    services.DatabaseFailure(_) ->
      json_response(500, error_json("request could not be completed"))
  }
}

fn create_location(
  request: wisp.Request,
  context: Context,
  organization_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.location_details(body) {
      Error(_) -> json_response(400, error_json("invalid location details"))
      Ok(#(name, timezone)) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            locations.create(
              context.database,
              user_id,
              organization_id,
              name,
              timezone,
            )
          {
            Ok(Nil) -> location_overview(context, user_id, organization_id)
            Error(error) -> location_error_response(error)
          }
        })
    }
  })
}

fn update_location(
  request: wisp.Request,
  context: Context,
  organization_id: String,
  location_id: String,
) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.location_details(body) {
      Error(_) -> json_response(400, error_json("invalid location details"))
      Ok(#(name, timezone)) ->
        with_authenticated_user(request, context, fn(user_id) {
          case
            locations.update(
              context.database,
              user_id,
              organization_id,
              location_id,
              name,
              timezone,
            )
          {
            Ok(Nil) -> location_overview(context, user_id, organization_id)
            Error(error) -> location_error_response(error)
          }
        })
    }
  })
}

fn location_overview(
  context: Context,
  user_id: String,
  organization_id: String,
) -> wisp.Response {
  case overview.for_user(context.database, user_id, organization_id) {
    Ok(Some(body)) -> json_response(200, body)
    Ok(None) -> json_response(404, error_json("not found"))
    Error(_) -> json_response(500, error_json("request could not be completed"))
  }
}

fn location_error_response(error: locations.LocationError) -> wisp.Response {
  case error {
    locations.InvalidName ->
      json_response(400, error_json("location name is required"))
    locations.InvalidTimezone ->
      json_response(400, error_json("valid IANA timezone required"))
    locations.Forbidden ->
      json_response(403, error_json("administrator access required"))
    locations.NotFound -> json_response(404, error_json("not found"))
    locations.DatabaseFailure(_) ->
      json_response(500, error_json("request could not be completed"))
  }
}

fn organization_detail(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
  case string.split(request.path, "/") {
    ["", "api", "organizations", organization_id] ->
      case request.method {
        http.Get ->
          with_authenticated_user(request, context, fn(user_id) {
            case overview.for_user(context.database, user_id, organization_id) {
              Ok(Some(body)) -> json_response(200, body)
              Ok(None) -> json_response(404, error_json("not found"))
              Error(_) ->
                json_response(500, error_json("request could not be completed"))
            }
          })
        http.Put ->
          request
          |> wisp.set_max_body_size(max_sign_in_body_bytes)
          |> wisp.require_bit_array_body(fn(body) {
            case http_requests.organization_name(body) {
              Error(_) ->
                json_response(400, error_json("invalid organization name"))
              Ok(name) ->
                with_authenticated_user(request, context, fn(user_id) {
                  case
                    profile.update_name(
                      context.database,
                      user_id,
                      organization_id,
                      name,
                    )
                  {
                    Ok(Nil) ->
                      case
                        overview.for_user(
                          context.database,
                          user_id,
                          organization_id,
                        )
                      {
                        Ok(Some(response_body)) ->
                          json_response(200, response_body)
                        Ok(None) -> json_response(404, error_json("not found"))
                        Error(_) ->
                          json_response(
                            500,
                            error_json("request could not be completed"),
                          )
                      }
                    Error(profile.InvalidName) ->
                      json_response(
                        400,
                        error_json("organization name is required"),
                      )
                    Error(profile.Forbidden) ->
                      json_response(
                        403,
                        error_json("administrator access required"),
                      )
                    Error(profile.NotFound) ->
                      json_response(404, error_json("not found"))
                    Error(profile.DatabaseFailure(_)) ->
                      json_response(
                        500,
                        error_json("request could not be completed"),
                      )
                  }
                })
            }
          })
        _ -> wisp.method_not_allowed([http.Get, http.Put])
      }
    _ -> wisp.json_response(error_json("not found"), 404)
  }
}

fn list_organizations(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
  with_authenticated_user(request, context, fn(user_id) {
    case overview.list_for_user(context.database, user_id) {
      Ok(organizations) ->
        json_response(200, "[" <> string.join(organizations, ",") <> "]")
      Error(_) ->
        json_response(500, error_json("request could not be completed"))
    }
  })
}

fn with_authenticated_user(
  request: wisp.Request,
  context: Context,
  respond: fn(String) -> wisp.Response,
) -> wisp.Response {
  case wisp.get_cookie(request, "kewkew_session", wisp.PlainText) {
    Error(Nil) -> json_response(401, error_json("authentication required"))
    Ok(token) ->
      case authentication.user_for_session(context.database, token) {
        Ok(user_id) -> respond(user_id)
        Error(authentication.InvalidCredentials) ->
          json_response(401, error_json("authentication required"))
        Error(authentication.DatabaseFailure(_)) ->
          json_response(500, error_json("request could not be completed"))
      }
  }
}

fn sign_in(request: wisp.Request, context: Context) -> wisp.Response {
  request
  |> wisp.set_max_body_size(max_sign_in_body_bytes)
  |> wisp.require_bit_array_body(fn(body) {
    case http_requests.credentials(body) {
      Error(_) -> json_response(400, error_json("invalid sign-in request"))
      Ok(#(email, password)) ->
        authentication.sign_in(context.database, email, password)
        |> sign_in_response(request)
    }
  })
}

fn sign_out(request: wisp.Request, context: Context) -> wisp.Response {
  let response = json_response(200, "{\"status\":\"ok\"}")
  let response = case
    wisp.get_cookie(request, "kewkew_session", wisp.PlainText)
  {
    Ok(token) ->
      case authentication.sign_out(context.database, token) {
        Ok(Nil) -> response
        Error(_) ->
          json_response(500, error_json("sign-out could not be completed"))
      }
    Error(Nil) -> response
  }
  let scheme = case request.host {
    "localhost" | "127.0.0.1" | "[::1]" if request.scheme == http.Http ->
      case http_request.get_header(request, "x-forwarded-proto") {
        Ok(_) -> http.Https
        Error(_) -> http.Http
      }
    _ -> http.Https
  }
  response
  |> response.expire_cookie("kewkew_session", cookie.defaults(scheme))
  |> wisp.set_header("cache-control", "no-store")
}

fn sign_in_response(
  result: Result(authentication.Session, authentication.AuthError),
  request: wisp.Request,
) -> wisp.Response {
  case result {
    Ok(session) -> sign_in_success(request, session)
    Error(authentication.InvalidCredentials) ->
      json_response(401, error_json("invalid email or password"))
    Error(authentication.DatabaseFailure(_)) ->
      json_response(500, error_json("sign-in could not be completed"))
  }
}

fn sign_in_success(
  request: wisp.Request,
  session: authentication.Session,
) -> wisp.Response {
  let user =
    json.object([
      #("id", json.string(session.user.id)),
      #("name", json.string(session.user.name)),
      #("email", json.string(session.user.email)),
      #("image", json.null()),
    ])
  json_response(200, json.to_string(json.object([#("user", user)])))
  |> wisp.set_cookie(
    request,
    "kewkew_session",
    session.token,
    wisp.PlainText,
    30 * 24 * 60 * 60,
  )
}

fn error_json(message: String) -> String {
  json.object([#("error", json.string(message))]) |> json.to_string
}

fn json_response(status: Int, body: String) -> wisp.Response {
  wisp.json_response(body, status)
  |> wisp.set_header("cache-control", "no-store")
}

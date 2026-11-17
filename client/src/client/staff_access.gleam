import client/organization as organization_view
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import shared.{
  type MembershipRole, type OrganizationOverview, type StaffInvitation, Admin,
  Sent,
}

/// Dedicated organization staff access screen.
pub fn view(
  overviews: Option(List(OrganizationOverview)),
  editor: organization_view.Model,
  invitations: List(StaffInvitation),
  lift: fn(organization_view.Message) -> message,
) -> Element(message) {
  html.section([attr.class("page")], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Manage")]),
        html.h1([], [html.text("Staff access")]),
        html.p([attr.class("subhead")], [
          html.text(
            "Invite teammates and grant their initial organization access.",
          ),
        ]),
      ]),
    ]),
    case overviews {
      None ->
        html.section([attr.class("card setup-card")], [
          html.p([], [html.text("Loading staff access…")]),
        ])
      Some(values) ->
        html.div(
          [attr.class("organization-overviews")],
          list.map(values, fn(overview: OrganizationOverview) {
            html.section([attr.class("staff-access-workspace")], [
              html.div([attr.class("staff-access-overview card")], [
                html.div([attr.class("staff-access-heading")], [
                  html.div([], [
                    html.p([attr.class("eyebrow")], [html.text("Organization")]),
                    html.h2([], [html.text(overview.organization.name)]),
                    html.p([attr.class("muted")], [
                      html.text("Manage who can work in this organization."),
                    ]),
                  ]),
                  html.span([attr.class("profile-access")], [
                    html.text(case overview.can_manage {
                      True -> "Admin access"
                      False -> "View only"
                    }),
                  ]),
                ]),
                html.div([attr.class("staff-access-stats")], [
                  access_stat(
                    "Locations",
                    int.to_string(list.length(overview.locations)),
                    "Available for assignments",
                  ),
                  access_stat("Roles", "2", "Admin and operator"),
                ]),
              ]),
              case overview.can_manage {
                True ->
                  html.div([attr.class("staff-access-sections")], [
                    organization_view.invitation_card(
                      overview.organization.id,
                      overview.locations,
                      editor,
                      lift,
                    ),
                    invitation_list(
                      overview,
                      list.filter(invitations, fn(invitation) {
                        invitation.organization_id == overview.organization.id
                        && invitation.delivery_state == Sent
                      }),
                    ),
                  ])
                False ->
                  html.section([attr.class("card setup-card")], [
                    html.p([], [
                      html.text(
                        "Only an organization administrator can invite staff or change access.",
                      ),
                    ]),
                  ])
              },
            ])
          }),
        )
    },
  ])
}

fn invitation_list(
  overview: OrganizationOverview,
  invitations: List(StaffInvitation),
) -> Element(message) {
  html.section([attr.class("staff-invitations card")], [
    html.div([attr.class("staff-invitations-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Team")]),
        html.h2([], [html.text("Sent invitations")]),
      ]),
      html.span([attr.class("location-count")], [
        html.text(int.to_string(list.length(invitations))),
      ]),
    ]),
    case invitations {
      [] ->
        html.div([attr.class("staff-invitations-empty")], [
          html.span([attr.class("empty-icon")], [html.text("✉")]),
          html.strong([], [html.text("No sent invitations yet")]),
          html.p([], [
            html.text(
              "Invitations you send will appear here with their role and access details.",
            ),
          ]),
        ])
      values ->
        html.div(
          [attr.class("staff-invitation-list")],
          list.map(values, fn(invitation: StaffInvitation) {
            html.article([attr.class("staff-invitation-row")], [
              html.div([attr.class("staff-invitation-person")], [
                html.span([attr.class("staff-invitation-avatar")], [
                  html.text("✉"),
                ]),
                html.div([], [
                  html.strong([], [html.text(invitation.invited_email)]),
                  html.small([], [html.text(role_label(invitation.role))]),
                ]),
              ]),
              html.div([attr.class("staff-invitation-locations")], [
                html.span([], [html.text("Access")]),
                html.strong([], [
                  html.text(invitation_access(invitation, overview)),
                ]),
              ]),
              html.div([attr.class("staff-invitation-expiry")], [
                html.span([], [html.text("Expires")]),
                html.strong([], [html.text(invitation.expires_at)]),
              ]),
              html.span([attr.class("invitation-status-pill")], [
                html.text(case invitation.accepted_at {
                  Some(_) -> "Accepted"
                  None -> "Sent"
                }),
              ]),
            ])
          }),
        )
    },
  ])
}

fn role_label(role: MembershipRole) -> String {
  case role {
    Admin -> "Administrator"
    _ -> "Operator"
  }
}

fn invitation_access(
  invitation: StaffInvitation,
  overview: OrganizationOverview,
) -> String {
  case invitation.role {
    Admin -> "All locations"
    _ -> {
      let names =
        overview.locations
        |> list.filter(fn(location) {
          list.contains(invitation.location_ids, location.location.id)
        })
        |> list.map(fn(location) { location.location.name })
      case names {
        [] -> "Assigned locations"
        _ -> string.join(names, ", ")
      }
    }
  }
}

fn access_stat(label: String, value: String, note: String) -> Element(message) {
  html.div([attr.class("staff-access-stat")], [
    html.span([], [html.text(label)]),
    html.strong([], [html.text(value)]),
    html.small([], [html.text(note)]),
  ])
}

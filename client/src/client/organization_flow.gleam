import client/organization as organization_view
import client/organization_overviews
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import shared.{type OrganizationOverview}

pub opaque type Model {
  Model(editor: organization_view.Model)
}

pub type Message {
  OrganizationAction(organization_view.Message)
}

pub type QueueSetup {
  QueueSetup(organization_id: String, location_id: String, service_id: String)
}

pub fn init() -> Model {
  Model(organization_view.init())
}

pub fn editor(model: Model) -> organization_view.Model {
  model.editor
}

/// Update organization administration and return data that the app shell
/// applies to its shared overview cache and route.
pub fn update(
  model: Model,
  message: Message,
) -> #(
  Model,
  Effect(Message),
  Option(OrganizationOverview),
  Option(QueueSetup),
  Bool,
) {
  let OrganizationAction(organization_message) = message
  let #(editor, editor_effect) =
    organization_view.update(model.editor, organization_message)
  let updated_overview =
    organization_overviews.from_message(organization_message)
  let queue_setup = case organization_message {
    organization_view.CreateQueue(organization_id, location_id, service_id) ->
      Some(QueueSetup(organization_id, location_id, service_id))
    _ -> None
  }
  let refresh_invitations = case organization_message {
    organization_view.InvitationCreated(Ok(_)) -> True
    _ -> False
  }
  #(
    Model(editor),
    effect.map(editor_effect, OrganizationAction),
    updated_overview,
    queue_setup,
    refresh_invitations,
  )
}

pub fn view(
  model: Model,
  overviews: Option(List(OrganizationOverview)),
  lift: fn(Message) -> message,
) -> Element(message) {
  html.section([attr.class("page")], [
    html.div([attr.class("page-heading")], [
      html.div([], [
        html.p([attr.class("eyebrow")], [html.text("Organization")]),
        html.h1([], [html.text(current_organization_name(overviews))]),
        html.p([attr.class("subhead")], [
          html.text("Locations, services, and queues in your workspace."),
        ]),
      ]),
    ]),
    overview_cards(model, overviews, lift),
  ])
}

fn current_organization_name(
  overviews: Option(List(OrganizationOverview)),
) -> String {
  case overviews {
    Some([overview, ..]) -> overview.organization.name
    _ -> "Your organization"
  }
}

fn overview_cards(
  model: Model,
  overviews: Option(List(OrganizationOverview)),
  lift: fn(Message) -> message,
) -> Element(message) {
  case overviews {
    None ->
      html.section([attr.class("card setup-card")], [
        html.p([], [html.text("Loading your organization…")]),
      ])
    Some([]) ->
      html.section([attr.class("card setup-card")], [
        html.h2([], [html.text("No active organization access")]),
        html.p([], [
          html.text("Contact an organization administrator for access."),
        ]),
      ])
    Some(values) ->
      html.div(
        [attr.class("organization-overviews")],
        list.map(values, fn(overview) {
          organization_view.overview_card(overview, model.editor, fn(message) {
            lift(OrganizationAction(message))
          })
        }),
      )
  }
}

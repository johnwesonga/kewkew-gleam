import client/organization as organization_view
import gleam/list
import gleam/option.{type Option, None, Some}
import shared.{type OrganizationOverview}

/// Extract overview payloads from mutations that replace cached organization data.
pub fn from_message(
  message: organization_view.Message,
) -> Option(OrganizationOverview) {
  case message {
    organization_view.Updated(Ok(updated)) -> Some(updated)
    organization_view.LocationSaved(Ok(updated)) -> Some(updated)
    organization_view.ServiceSaved(Ok(updated)) -> Some(updated)
    _ -> None
  }
}

/// Replace the cached overview for an organization with the server response.
/// When no overview is cached yet, keep the response as the first entry.
pub fn replace(
  current: Option(List(OrganizationOverview)),
  updated: OrganizationOverview,
) -> Option(List(OrganizationOverview)) {
  case current {
    Some(overviews) ->
      Some(
        list.map(overviews, fn(overview) {
          case overview.organization.id == updated.organization.id {
            True -> updated
            False -> overview
          }
        }),
      )
    _ -> Some([updated])
  }
}

import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/json
import gleam/result
import gleam/string

pub type ResendError {
  InvalidRequest
  ProviderRejected(status: Int)
  NetworkFailure
}

/// Render invitation content without sending it. Kept public for focused
/// template tests and alternate delivery adapters.
pub fn invitation_content(
  organization: String,
  role: String,
  acceptance_url: String,
  expires_at: String,
) -> #(String, String) {
  #(
    email_html(organization, role, acceptance_url, expires_at),
    email_text(organization, role, acceptance_url, expires_at),
  )
}

/// Send a staff invitation through Resend. The API key is passed by the
/// server's trusted environment and is never stored or returned.
pub fn send_invitation(
  api_key: String,
  from: String,
  to: String,
  organization: String,
  role: String,
  acceptance_url: String,
  expires_at: String,
) -> Result(Nil, ResendError) {
  send_invitation_with_transport(
    api_key,
    from,
    to,
    organization,
    role,
    acceptance_url,
    expires_at,
    httpc.send,
  )
}

/// Send through an HTTP transport, allowing provider responses to be tested.
pub fn send_invitation_with_transport(
  api_key: String,
  from: String,
  to: String,
  organization: String,
  role: String,
  acceptance_url: String,
  expires_at: String,
  send: fn(request.Request(String)) ->
    Result(response.Response(String), httpc.HttpError),
) -> Result(Nil, ResendError) {
  use req <- result.try(
    request.to("https://api.resend.com/emails")
    |> result.replace_error(InvalidRequest),
  )
  let body =
    json.object([
      #("from", json.string(from)),
      #("to", json.array([to], json.string)),
      #(
        "subject",
        json.string("You're invited to " <> organization <> " on Kewkew"),
      ),
      #(
        "html",
        json.string(email_html(organization, role, acceptance_url, expires_at)),
      ),
      #(
        "text",
        json.string(email_text(organization, role, acceptance_url, expires_at)),
      ),
    ])
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("authorization", "Bearer " <> api_key)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(json.to_string(body))
  case send(req) {
    Ok(response) if response.status >= 200 && response.status < 300 -> Ok(Nil)
    Ok(response) -> Error(ProviderRejected(response.status))
    Error(_) -> Error(NetworkFailure)
  }
}

fn email_html(
  organization: String,
  role: String,
  url: String,
  expires_at: String,
) -> String {
  "<div style=\"font-family:Arial,sans-serif;color:#17251f;max-width:560px;margin:auto\"><p style=\"color:#176b4b;font-weight:bold\">KEWKEW STAFF INVITATION</p><h1>You're invited to "
  <> escape(organization)
  <> "</h1><p>You've been invited to join as an "
  <> escape(role)
  <> ". Set up your account using the secure link below.</p><p><a href=\""
  <> escape(url)
  <> "\" style=\"display:inline-block;background:#176b4b;color:white;padding:13px 18px;border-radius:10px;text-decoration:none\">Accept invitation</a></p><p>This single-use link expires at "
  <> escape(expires_at)
  <> ". If you weren't expecting this email, you can ignore it.</p></div>"
}

fn email_text(
  organization: String,
  role: String,
  url: String,
  expires_at: String,
) -> String {
  "You're invited to "
  <> organization
  <> " on Kewkew as an "
  <> role
  <> ". Accept the invitation: "
  <> url
  <> " . This single-use link expires at "
  <> expires_at
  <> ". If you weren't expecting this email, ignore it."
}

fn escape(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}

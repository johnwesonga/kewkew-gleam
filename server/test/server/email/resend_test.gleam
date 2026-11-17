import gleam/string
import server/email/resend

pub fn invitation_email_contains_secure_link_and_escaped_context_test() {
  let #(html, text) =
    resend.invitation_content(
      "A <Clinic & Co>",
      "operator",
      "https://app.example.com/invite/accept?token=secret-token",
      "2026-12-01T00:00:00Z",
    )
  let assert True = string.contains(html, "A &lt;Clinic &amp; Co&gt;")
  let assert True =
    string.contains(
      html,
      "https://app.example.com/invite/accept?token=secret-token",
    )
  let assert True = string.contains(html, "2026-12-01T00:00:00Z")
  let assert True = string.contains(text, "operator")
  let assert True =
    string.contains(
      text,
      "https://app.example.com/invite/accept?token=secret-token",
    )
}

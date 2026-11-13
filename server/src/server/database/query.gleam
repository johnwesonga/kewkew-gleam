import gleam/dynamic/decode
import gleam/result
import gleam/string
import sqlight

/// Run a SQL query whose selected columns all decode to strings.
///
/// Keeping this helper in the server database package avoids pulling the
/// server-only SQLight dependency into the cross-target shared package.
pub fn strings(
  connection: sqlight.Connection,
  sql: String,
  parameters: List(sqlight.Value),
  on_error: fn(String) -> error,
) -> Result(List(List(String)), error) {
  sqlight.query(
    sql,
    on: connection,
    with: parameters,
    expecting: decode.list(decode.string),
  )
  |> result.map_error(fn(error) { on_error(string.inspect(error)) })
}

//// JSON request body decoders for HTTP endpoints.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/result

pub fn credentials(body: BitArray) -> Result(#(String, String), Nil) {
  json.parse_bits(body, credentials_decoder()) |> result.replace_error(Nil)
}

pub fn organization_name(body: BitArray) -> Result(String, Nil) {
  json.parse_bits(body, organization_name_decoder())
  |> result.replace_error(Nil)
}

pub fn location_details(body: BitArray) -> Result(#(String, String), Nil) {
  json.parse_bits(body, location_details_decoder()) |> result.replace_error(Nil)
}

pub fn service_details(body: BitArray) -> Result(#(String, String), Nil) {
  json.parse_bits(body, service_details_decoder()) |> result.replace_error(Nil)
}

fn service_details_decoder() -> decode.Decoder(#(String, String)) {
  use name <- decode.field("name", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  decode.success(
    #(name, case description {
      Some(value) -> value
      None -> ""
    }),
  )
}

fn location_details_decoder() -> decode.Decoder(#(String, String)) {
  use name <- decode.field("name", decode.string)
  use timezone <- decode.field("timezone", decode.string)
  decode.success(#(name, timezone))
}

fn organization_name_decoder() -> decode.Decoder(String) {
  use name <- decode.field("name", decode.string)
  decode.success(name)
}

fn credentials_decoder() -> decode.Decoder(#(String, String)) {
  use email <- decode.field("email", decode.string)
  use password <- decode.field("password", decode.string)
  decode.success(#(email, password))
}

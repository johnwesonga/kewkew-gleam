import gleam/bit_array
import gleam/crypto

/// Generate a random URL-safe identifier from 16 cryptographic random bytes.
pub fn new() -> String {
  crypto.strong_random_bytes(16)
  |> bit_array.base64_url_encode(False)
}

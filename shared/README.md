# Kewkew shared types

This portable Gleam package contains domain and API contract types used by both the JavaScript client and Erlang server. The types are based on business entities in [`server/db/database.sql`](../server/db/database.sql).

Authentication credentials, token digests, database session records, and other server-only implementation details do not belong in this package.

JSON encoders and decoders for the shared records and enums live in `shared/json`. Encoders return `gleam/json.Json`; decoders return `gleam/dynamic/decode.Decoder` values that can be passed to `gleam/json.parse`.

## Development

```sh
gleam deps download
gleam check
gleam test
```

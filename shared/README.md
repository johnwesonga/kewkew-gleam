# Kewkew shared types

This portable Gleam package contains domain and API contract types used by both the JavaScript client and Erlang server. The types are based on business entities in [`server/db/database.sql`](../server/db/database.sql).

Authentication credentials, token digests, database session records, and other server-only implementation details do not belong in this package.

## Development

```sh
gleam deps download
gleam check
gleam test
```

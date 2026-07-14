# Delight

[![Elixir CI](https://github.com/supermaciz/delight/actions/workflows/elixir.yml/badge.svg)](https://github.com/supermaciz/delight/actions/workflows/elixir.yml)
[![codecov](https://codecov.io/gh/supermaciz/delight/graph/badge.svg)](https://codecov.io/gh/supermaciz/delight)

A small REST API that wraps Deezer's public Web API to return an artist's
albums. On the first request for an artist, the data is fetched from Deezer and
persisted in Postgres (name, Deezer ID, and albums with their release dates);
subsequent requests are served from the database.

The database acts as a time-limited cache: a persisted artist is served locally
until it goes stale (its `updated_at` is older than `:albums_ttl_hours`, 24h by
default — see `config/config.exs`), after which the next request re-syncs the
artist from Deezer: it picks up albums released in the meantime and drops any
album Deezer no longer lists, keeping the local copy an exact mirror.

Deezer throttles per IP address (50 requests per 5 seconds), so outgoing calls go
through a shared token bucket (`Delight.DeezerAPI.RateLimiter`): a burst of 10,
then 8 requests per second — see `config/config.exs`. A caller waits for the
bucket to refill, and gives up after `:timeout` with a `429 Too Many Requests`.

## Requirements

* Elixir / Erlang (see `.tool-versions` or `mix.exs` for versions)
* PostgreSQL running locally (defaults in `config/dev.exs`)

### Environment variables

Production requires the following environment variables:

| Variable | Description |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection URL |
| `SECRET_KEY_BASE` | Secret used to sign and encrypt application data |

## Getting started

The easiest way to start the application and PostgreSQL (with migrations) is with Docker Compose:

```sh
docker compose up
```

The API will be available at <http://localhost:4000>.

Alternatively, run the application locally:

```sh
mix setup          # install deps, create and migrate the database
mix phx.server     # start the server on http://localhost:4000
```

## Usage

The API exposes a single endpoint:

```
GET /api/artists/albums?name=<artist name>
```

Example:

```sh
curl "http://localhost:4000/api/artists/albums?name=Daft%20Punk"
```

Response:

```json
{
  "data": [
    {
      "name": "Daft Punk",
      "deezer_id": 27,
      "albums": [
        { "title": "Random Access Memories", "release_date": "2013-05-17", "deezer_id": 6575789 },
        { "title": "Discovery", "release_date": "2001-03-07", "deezer_id": 302127 }
      ]
    }
  ]
}
```

Because different artists can share the same name, `data` is a list of matching
artists. If no artist matches, the API responds with `404` and
`{"errors": {"detail": "Not Found"}}`.

The full API contract is documented in [`openapi.yaml`](openapi.yaml).

## Tests

```sh
mix test
```

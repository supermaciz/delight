# Delight

[![Elixir CI](https://github.com/supermaciz/delight/actions/workflows/elixir.yml/badge.svg)](https://github.com/supermaciz/delight/actions/workflows/elixir.yml)
[![codecov](https://codecov.io/gh/supermaciz/delight/graph/badge.svg)](https://codecov.io/gh/supermaciz/delight)

A small REST API that wraps Deezer's public Web API to return an artist's
albums. On the first request for an artist, the data is fetched from Deezer and
persisted in Postgres (name, Deezer ID, and albums with their release dates);
subsequent requests are served from the database.

## Requirements

* Elixir / Erlang (see `.tool-versions` or `mix.exs` for versions)
* PostgreSQL running locally (defaults in `config/dev.exs`)

## Getting started

The easiest way to start the application and PostgreSQL is with Docker Compose:

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

The full API contract is documented in [`openapi.yaml`](openapi.yaml) (paste it
into <https://editor.swagger.io> to browse it).

## Tests

```sh
mix test
```

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

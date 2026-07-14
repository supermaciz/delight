# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :delight,
  ecto_repos: [Delight.Repo],
  generators: [timestamp_type: :utc_datetime]

# How long a persisted artist's albums are served from the local cache before
# `Delight.Music.find_or_import_artists/1` re-syncs them from Deezer.
config :delight, Delight.Music, albums_ttl_hours: 24

# Configure the endpoint
config :delight, DelightWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: DelightWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Delight.PubSub,
  live_view: [signing_salt: "niGQUms1"]

# Deezer throttles at 50 requests per 5 seconds per IP address. A sliding window
# holds to that quota over *any* 5-second period, where a token bucket of the
# same size would let a full burst be followed by the refill. A caller waits up
# to `:timeout` for capacity before giving up.
config :delight, Delight.DeezerAPI.RateLimiter,
  scale: :timer.seconds(5),
  limit: 50,
  timeout: :timer.seconds(5)

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

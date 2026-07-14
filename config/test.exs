import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :delight, Delight.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "delight_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :delight, DelightWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "6GZbQuySHuu20DvZuCt+SZ3dcgXLLVnFtkU/Y3qbgCwBMPwb78l4LkEaff+kTpCS",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :delight, Delight.DeezerAPI, req_options: [plug: {Req.Test, Delight.DeezerAPI}]

# The window is global: leave it wide open so it never throttles unrelated
# tests. Tests that exercise throttling narrow it themselves.
config :delight, Delight.DeezerAPI.RateLimiter,
  scale: :timer.seconds(1),
  limit: 100_000

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

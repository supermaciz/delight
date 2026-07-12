defmodule Delight.Repo do
  use Ecto.Repo,
    otp_app: :delight,
    adapter: Ecto.Adapters.Postgres
end

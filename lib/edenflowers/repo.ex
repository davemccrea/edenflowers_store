defmodule Edenflowers.Repo do
  use Ecto.Repo,
    otp_app: :edenflowers,
    adapter: Ecto.Adapters.Postgres
end

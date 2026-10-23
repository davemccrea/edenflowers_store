defmodule Edenflowers.Repo do
  @moduledoc """
  Ecto repository and AshPostgres adapter configuration for the shop database.
  """

  use AshPostgres.Repo,
    otp_app: :edenflowers

  def installed_extensions do
    ["ash-functions", "citext"]
  end

  def prefer_transaction? do
    false
  end

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end

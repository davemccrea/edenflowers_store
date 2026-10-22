defmodule EdenflowersWeb.HealthController do
  @moduledoc """
  Polled by Better Stack. Answers 200 only when the app can reach the database;
  a dead database raises, so the check sees a 500.
  """
  use EdenflowersWeb, :controller

  def show(conn, _params) do
    Ecto.Adapters.SQL.query!(Edenflowers.Repo, "SELECT 1")

    conn
    |> put_resp_header("cache-control", "no-store")
    |> text("ok")
  end
end

defmodule EdenflowersWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use EdenflowersWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint EdenflowersWeb.Endpoint

      use EdenflowersWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import EdenflowersWeb.ConnCase
    end
  end

  setup tags do
    Edenflowers.DataCase.setup_sandbox(tags)
    Edenflowers.DataCase.stub_card_lookup()
    Edenflowers.DataCase.stub_papra_rename()
    # Visitors with no language preference get Swedish; tests read as an English browser.
    {:ok, conn: Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("accept-language", "en")}
  end

  @doc """
  Makes `order` this browser's cart, as its first add to cart would: stamps it
  with a visitor_id and puts that visitor_id in the session.
  """
  def with_cart(conn, order) do
    visitor_id = order.visitor_id || Ecto.UUID.generate()
    Ash.Seed.update!(order, %{visitor_id: visitor_id})
    Plug.Test.init_test_session(conn, %{visitor_id: visitor_id})
  end

  @doc """
  Signs `user` into the connection. `session` is for whatever else the page
  reads from it.
  """
  def log_in(conn, user, session \\ %{}) do
    conn
    |> Plug.Test.init_test_session(session)
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  @doc """
  A setup callback for an admin's pages: signs a generated admin in, and puts
  her in the context for the test to run actions as.
  """
  def log_in_admin(%{conn: conn}) do
    admin = Generator.generate(Generator.admin_user()) |> Generator.with_token()
    %{conn: log_in(conn, admin), admin: admin}
  end
end

defmodule EdenflowersWeb.ConnCase do
  @moduledoc """
  Provides a connection, verified routes and connection helpers for web tests.

  Every test starts a SQL sandbox owner so database changes are rolled back
  afterwards. `async: true` gives each test an isolated database connection;
  synchronous tests share theirs with other processes involved in the test.
  Tests that change global application configuration must run synchronously.
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
    Edenflowers.DataCase.stub_papra_update()
    # The Overview asks for the weather; tests that show it stub a forecast.
    Req.Test.stub(Edenflowers.External.WeatherAPI, &Plug.Conn.send_resp(&1, 503, ""))
    # Visitors with no language preference get Swedish; tests read as an English browser.
    {:ok, conn: Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("accept-language", "en")}
  end

  @doc """
  Retries `assertion` every 10 ms until it passes, and after a second lets its
  failure through. Use it to wait for something another process does, such as
  a LiveView refreshing after a PubSub notification, in place of sleeping.
  """
  def eventually(assertion, attempts \\ 100) do
    assertion.()
  rescue
    error in ExUnit.AssertionError ->
      if attempts > 1 do
        Process.sleep(10)
        eventually(assertion, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  @doc """
  Associates `order` with this browser's session, as adding its first cart item
  would. Reuses the order's visitor ID if present, or generates one, and stores
  the same ID on the order and in the session.
  """
  def with_cart(conn, order) do
    visitor_id = order.visitor_id || Ecto.UUID.generate()
    Ash.Seed.update!(order, %{visitor_id: visitor_id})
    Plug.Test.init_test_session(conn, %{visitor_id: visitor_id})
  end

  @doc """
  Signs `user` into the connection and initializes the session with any
  additional values supplied in `session`.
  """
  def log_in(conn, user, session \\ %{}) do
    conn
    |> Plug.Test.init_test_session(session)
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  @doc """
  Signs in a generated admin for admin-page tests. Returns the authenticated
  connection and the admin in the test context so actions can use that actor.
  """
  def log_in_admin(%{conn: conn}) do
    admin = Generator.generate(Generator.admin_user()) |> Generator.with_token()
    %{conn: log_in(conn, admin), admin: admin}
  end
end

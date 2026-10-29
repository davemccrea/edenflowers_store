defmodule EdenflowersWeb.Admin.ConnectedCustomersTest do
  use EdenflowersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :log_in_admin

  test "overview updates when a store visitor connects and disconnects", %{conn: conn} do
    {:ok, admin, _html} = live(conn, ~p"/admin")
    guest_conn = build_conn() |> put_req_header("accept-language", "en")
    {:ok, guest, _html} = live(guest_conn, ~p"/en/store")

    eventually(fn -> assert has_element?(admin, "#anonymous-visitors-count", "1 anonymous visitor") end)

    GenServer.stop(guest.pid)

    eventually(fn -> refute has_element?(admin, "#anonymous-visitors-count") end)
  end

  test "admin browsing the store is excluded", %{conn: conn, admin: user} do
    {:ok, _store, _html} = live(conn, ~p"/en/store")
    {:ok, view, _html} = live(conn, ~p"/admin")

    eventually(fn ->
      refute has_element?(view, "#connected-customers a[href='/admin/customers/#{user.id}']")
      assert has_element?(view, "#connected-customers-count", "0")
    end)
  end

  test "groups anonymous visitors and bounds the named list without dropping customers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#connected-customers", "Online customers")
    eventually(fn -> assert has_element?(view, "#connected-customers", "No customers online") end)

    for index <- 1..30 do
      user = %{id: Ecto.UUID.generate(), name: "Online customer #{index}"}
      EdenflowersWeb.Presence.track_customer(user, Ecto.UUID.generate())
    end

    for _ <- 1..12 do
      EdenflowersWeb.Presence.track_customer(nil, Ecto.UUID.generate())
    end

    eventually(fn ->
      assert has_element?(view, "#connected-customers-count", "42")
      assert has_element?(view, "#anonymous-visitors-count", "12 anonymous visitors")

      assert Enum.count(
               view
               |> element("#online-customers-list")
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("li")
             ) == 30

      refute has_element?(view, "#connected-customers", "No customers online")
    end)
  end

  defp eventually(assertion, attempts \\ 100) do
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
end

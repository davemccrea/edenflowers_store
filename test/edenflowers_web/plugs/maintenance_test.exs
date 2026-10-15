defmodule EdenflowersWeb.Plugs.MaintenanceTest do
  use EdenflowersWeb.ConnCase, async: false

  test "redirects /back-soon to the homepage when maintenance mode is off", %{conn: conn} do
    conn = get(conn, "/back-soon")
    assert redirected_to(conn) == "/"
  end

  describe "when maintenance mode is on" do
    setup do
      Application.put_env(:edenflowers, :maintenance_mode, true)
      on_exit(fn -> Application.delete_env(:edenflowers, :maintenance_mode) end)
    end

    test "redirects store pages to /back-soon", %{conn: conn} do
      assert conn |> get("/store") |> redirected_to() == "/back-soon"
    end

    test "lets the sign-in page through", %{conn: conn} do
      assert conn |> get("/sign-in") |> html_response(200)
    end

    test "lets admin paths reach their own auth check", %{conn: conn} do
      assert conn |> get("/admin/orders") |> redirected_to() =~ "/sign-in"
    end
  end
end

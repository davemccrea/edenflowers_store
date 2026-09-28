defmodule EdenflowersWeb.Plugs.MaintenanceTest do
  use EdenflowersWeb.ConnCase, async: true

  test "redirects /back-soon to the homepage when maintenance mode is off", %{conn: conn} do
    conn = get(conn, "/back-soon")
    assert redirected_to(conn) == "/"
  end
end

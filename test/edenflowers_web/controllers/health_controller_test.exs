defmodule EdenflowersWeb.HealthControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  test "answers ok uncached when the database is reachable", %{conn: conn} do
    conn = get(conn, "/health")

    assert text_response(conn, 200) == "ok"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end
end

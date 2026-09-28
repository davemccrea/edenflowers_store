defmodule EdenflowersWeb.Plugs.CaptureReturnToTest do
  use EdenflowersWeb.ConnCase, async: true

  describe "GET /sign-in" do
    test "stores a safe return_to in the session", %{conn: conn} do
      conn = get(conn, "/sign-in", return_to: "/account")
      assert get_session(conn, :return_to) == "/account"
    end

    test "stores a path with a query string", %{conn: conn} do
      conn = get(conn, "/sign-in?return_to=%2Fstore%3Fcategory%3Dbouquets")
      assert get_session(conn, :return_to) == "/store?category=bouquets"
    end

    test "ignores external return targets", %{conn: conn} do
      conn = get(conn, "/sign-in", return_to: "https://evil.example.com/")
      assert get_session(conn, :return_to) == nil
    end

    test "ignores protocol-relative return targets", %{conn: conn} do
      conn = get(conn, "/sign-in", return_to: "//evil.example.com/")
      assert get_session(conn, :return_to) == nil
    end

    test "ignores return targets pointing back at the sign-in page", %{conn: conn} do
      conn = get(conn, "/sign-in", return_to: "/sign-in")
      assert get_session(conn, :return_to) == nil
    end

    test "ignores return targets pointing into the auth flow", %{conn: conn} do
      conn = get(conn, "/sign-in", return_to: "/auth/user/google")
      assert get_session(conn, :return_to) == nil
    end

    test "no query param leaves the session value untouched", %{conn: conn} do
      conn =
        conn
        |> init_test_session(return_to: "/account")
        |> get("/sign-in")

      assert get_session(conn, :return_to) == "/account"
    end
  end

  describe "other paths" do
    test "does not write the session", %{conn: conn} do
      conn = get(conn, "/", return_to: "/account")
      assert get_session(conn, :return_to) == nil
    end
  end
end

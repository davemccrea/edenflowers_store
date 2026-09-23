defmodule EdenflowersWeb.AuthControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias EdenflowersWeb.Auth.AuthController

  describe "success/4" do
    test "redirects admins to / when no return_to was captured", %{conn: conn} do
      admin = generate(admin_user()) |> with_token()

      conn =
        conn
        |> init_auth_session(%{})
        |> AuthController.success({:password, :sign_in}, admin, nil)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects non-admin users to / when no return_to was captured", %{conn: conn} do
      user = generate(admin_user(admin: false)) |> with_token()

      conn =
        conn
        |> init_auth_session(%{})
        |> AuthController.success({:password, :sign_in}, user, nil)

      assert redirected_to(conn) == ~p"/"
    end

    test "preserves captured return_to for admins", %{conn: conn} do
      admin = generate(admin_user()) |> with_token()

      conn =
        conn
        |> init_auth_session(return_to: "/admin/orders")
        |> AuthController.success({:password, :sign_in}, admin, nil)

      assert redirected_to(conn) == ~p"/admin/orders"
      refute get_session(conn, :return_to)
    end
  end

  describe "failure/3" do
    test "a wrong OTP sends the user back to the code step for the same email", %{conn: conn} do
      conn =
        %{conn | params: %{"user" => %{"email" => "jennie@example.com", "otp" => "WRONG1"}}}
        |> init_auth_session(%{})
        |> AuthController.failure({:otp, :sign_in}, nil)

      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :otp_email) == "jennie@example.com"
    end
  end

  describe "GET /sign-in after a failed OTP" do
    test "opens on the code step for the flashed email", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{"phoenix_flash" => %{"otp_email" => "jennie@example.com"}})

      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ "jennie@example.com"
      assert html =~ "user[otp]"
    end
  end

  describe "GET /sign-in" do
    test "redirects an already-signed-in admin to /", %{conn: conn} do
      admin = generate(admin_user()) |> with_token()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Helpers.store_in_session(admin)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/sign-in")
    end

    test "redirects an already-signed-in non-admin user to /", %{conn: conn} do
      user = generate(admin_user(admin: false)) |> with_token()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Helpers.store_in_session(user)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/sign-in")
    end
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end

  defp init_auth_session(conn, session) do
    conn
    |> Plug.Test.init_test_session(session)
    |> Phoenix.Controller.fetch_flash([])
  end
end

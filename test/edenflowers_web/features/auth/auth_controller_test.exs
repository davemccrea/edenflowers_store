defmodule EdenflowersWeb.Auth.AuthControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias EdenflowersWeb.Auth.AuthController

  describe "success/4" do
    test "redirects admins to / when no return_to was captured", %{conn: conn} do
      admin = generate(admin_user()) |> with_token()

      conn =
        conn
        |> init_auth_session(%{})
        |> AuthController.success({:otp, :sign_in}, admin, nil)

      assert redirected_to(conn) == ~p"/en"
    end

    test "redirects non-admin users to / when no return_to was captured", %{conn: conn} do
      user = generate(admin_user(admin: false)) |> with_token()

      conn =
        conn
        |> init_auth_session(%{})
        |> AuthController.success({:otp, :sign_in}, user, nil)

      assert redirected_to(conn) == ~p"/en"
    end

    test "preserves captured return_to for admins", %{conn: conn} do
      admin = generate(admin_user()) |> with_token()

      conn =
        conn
        |> init_auth_session(return_to: "/admin/orders")
        |> AuthController.success({:otp, :sign_in}, admin, nil)

      assert redirected_to(conn) == ~p"/admin/orders"
      refute get_session(conn, :return_to)
    end
  end

  describe "failure/3" do
    test "a wrong OTP sends the user back to the code step for the same email", %{conn: conn} do
      conn =
        %{conn | params: %{"user" => %{"email" => "jennie@example.com", "otp" => "00000000"}}}
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

      conn = log_in(conn, admin)

      assert {:error, {:redirect, %{to: "/en"}}} = live(conn, ~p"/sign-in")
    end

    test "redirects an already-signed-in non-admin user to /", %{conn: conn} do
      user = generate(admin_user(admin: false)) |> with_token()

      conn = log_in(conn, user)

      assert {:error, {:redirect, %{to: "/en"}}} = live(conn, ~p"/sign-in")
    end
  end

  describe "DELETE /sign-out?everywhere=true" do
    test "signs the user out of their other devices too", %{conn: conn} do
      user = generate(admin_user(admin: false))
      this_device = with_token(user)
      other_device = with_token(user)

      conn = conn |> log_in(this_device) |> delete(~p"/sign-out?everywhere=true")

      assert redirected_to(conn) == ~p"/en"
      refute get_session(conn, "user_token")

      assert {:error, {:redirect, %{to: "/sign-in" <> _}}} =
               build_conn() |> log_in(other_device) |> live(~p"/account")
    end

    test "a plain sign-out leaves other devices signed in", %{conn: conn} do
      user = generate(admin_user(admin: false))
      this_device = with_token(user)
      other_device = with_token(user)

      conn |> log_in(this_device) |> delete(~p"/sign-out")

      assert {:ok, _view, _html} = build_conn() |> log_in(other_device) |> live(~p"/account")
    end

    test "nobody can sign another user out" do
      user = generate(admin_user(admin: false)) |> with_token()
      stranger = generate(admin_user(admin: false))

      assert {:error, %Ash.Error.Forbidden{}} = Edenflowers.Accounts.log_out_everywhere(user, actor: stranger)
      assert {:ok, _view, _html} = build_conn() |> log_in(user) |> live(~p"/account")
    end
  end

  defp init_auth_session(conn, session) do
    conn
    |> Plug.Test.init_test_session(session)
    |> Phoenix.Controller.fetch_flash([])
  end
end

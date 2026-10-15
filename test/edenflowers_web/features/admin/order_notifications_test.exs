defmodule EdenflowersWeb.Admin.OrderNotificationsTest do
  # Not async: the VAPID keys are application env.
  use EdenflowersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Accounts

  @subscription %{
    "endpoint" => "https://push.example.com/abc",
    "keys" => %{
      "p256dh" => "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
      "auth" => "BTBZMqHH6r4Tts7J_aSIgg"
    }
  }

  setup %{conn: conn} do
    Application.put_env(:web_push_ex, :vapid, Map.to_list(Edenflowers.WebPush.generate_keys()))
    on_exit(fn -> Application.delete_env(:web_push_ex, :vapid) end)

    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)
    %{conn: conn, admin: admin}
  end

  test "admin pages install as the admin app, the storefront as the shop", %{conn: conn} do
    assert conn |> get(~p"/admin/account") |> html_response(200) =~ ~s(href="/admin.webmanifest)
    assert conn |> get(~p"/") |> html_response(200) =~ ~s(href="/site.webmanifest)
  end

  test "the account page's switch saves and forgets this device", %{conn: conn, admin: admin} do
    {:ok, view, html} = live(conn, ~p"/admin/account")
    assert html =~ "New order notifications"

    render_hook(view, "push_subscribed", @subscription)
    assert_reply view, %{ok: true}
    assert [%{endpoint: "https://push.example.com/abc"}] = Accounts.list_push_subscriptions!(actor: admin)

    render_hook(view, "push_unsubscribed", %{"endpoint" => "https://push.example.com/abc"})
    assert_reply view, %{ok: true}
    assert Accounts.list_push_subscriptions!(actor: admin) == []
  end

  test "a malformed subscription is refused", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(conn, ~p"/admin/account")

    render_hook(view, "push_subscribed", %{"endpoint" => "https://push.example.com/abc"})
    assert_reply view, %{ok: false}
    assert Accounts.list_push_subscriptions!(actor: admin) == []
  end

  test "the Overview card subscribes this device", %{conn: conn, admin: admin} do
    {:ok, view, html} = live(conn, ~p"/admin")
    assert html =~ "Get new orders on this phone"

    render_hook(view, "push_subscribed", @subscription)
    assert_reply view, %{ok: true}
    assert [_subscription] = Accounts.list_push_subscriptions!(actor: admin)
  end

  test "without VAPID keys there's no setting or offer", %{conn: conn} do
    Application.delete_env(:web_push_ex, :vapid)

    {:ok, _view, html} = live(conn, ~p"/admin/account")
    refute html =~ "New order notifications"

    {:ok, _view, html} = live(conn, ~p"/admin")
    refute html =~ "Get new orders on this phone"
  end
end

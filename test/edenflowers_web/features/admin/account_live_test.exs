defmodule EdenflowersWeb.Admin.AccountLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  test "admin uploads, views and removes a profile picture", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/account")

    picture =
      file_input(view, "#avatar-form", :avatar, [
        %{name: "me.png", content: "fake-png-bytes", type: "image/png"}
      ])

    assert {:error, {:redirect, %{to: "/admin/account"}}} = render_upload(picture, "me.png")

    response = get(conn, ~p"/admin/account/avatar")
    assert response.status == 200
    assert response.resp_body == "fake-png-bytes"
    assert response |> get_resp_header("content-type") == ["image/png"]

    [etag] = get_resp_header(response, "etag")
    assert conn |> put_req_header("if-none-match", etag) |> get(~p"/admin/account/avatar") |> Map.get(:status) == 304

    {:ok, view, html} = live(conn, ~p"/admin/account")
    assert html =~ ~s(src="/admin/account/avatar")

    assert {:error, {:redirect, _}} = view |> element("button", "Remove") |> render_click()
    assert get(conn, ~p"/admin/account/avatar").status == 404
  end

  test "admin's colour picker choice sticks and colours the back office", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/account")

    render_hook(view, "update_appearance", %{
      "admin_hue" => 325,
      "admin_chroma" => 70,
      "admin_lightness" => 30,
      "admin_grain" => 0
    })

    body = conn |> get(~p"/admin") |> html_response(200)
    assert body =~ "--admin-hue: 325; --admin-chroma: 70; --admin-lightness: 30; --admin-grain: 0"
  end

  test "admin picks the admin language in account settings", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/account")

    for locale <- Edenflowers.Locales.admin() do
      assert has_element?(
               view,
               ~s|#admin-locale-picker option[value="/admin-locale/#{locale}"]|
             )
    end

    refute has_element?(view, ~s|#admin-locale-picker option[value="/admin-locale/fi"]|)

    {:ok, _view, html} = live(conn, ~p"/admin/orders")
    refute html =~ "/locale/"
  end

  test "Finnish storefront visitors see Swedish admin without changing their customer language", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    key = Localize.Plug.PutLocale.session_key()
    conn = conn |> log_in(admin) |> init_test_session(%{key => "fi"})

    {:ok, view, html} = live(conn, ~p"/admin/account")
    assert has_element?(view, ~s|#admin-locale-picker option[value="/admin-locale/sv-FI"][selected]|)

    assert html =~
             Gettext.with_locale(EdenflowersWeb.Gettext, "sv", fn ->
               Gettext.dgettext(EdenflowersWeb.Gettext, "admin", "This device")
             end)

    response = get(conn, ~p"/admin/account")
    assert get_session(response, key) == "fi"

    response = conn |> get(~p"/admin-locale/en-GB") |> recycle() |> get(~p"/admin/account")
    assert get_session(response, key) == "fi"
    {:ok, view, html} = live(recycle(response), ~p"/admin/account")
    assert has_element?(view, ~s|#admin-locale-picker option[value="/admin-locale/en-GB"][selected]|)
    assert html =~ "This device"

    response = response |> recycle() |> get(~p"/account")
    assert get_session(response, key) == "fi"
    assert html_response(response, 200) =~ ~s|lang="fi"|
  end

  test "non-admins cannot fetch an avatar", %{conn: conn} do
    user = generate(admin_user(admin: false)) |> with_token()
    conn = log_in(conn, user)

    assert get(conn, ~p"/admin/account/avatar").status == 404
  end
end

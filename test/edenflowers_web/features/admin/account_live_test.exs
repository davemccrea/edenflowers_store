defmodule EdenflowersWeb.Admin.AccountLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers

  test "admin uploads, views and removes a profile picture", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

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

  test "non-admins cannot fetch an avatar", %{conn: conn} do
    user = generate(admin_user(admin: false)) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(user)

    assert get(conn, ~p"/admin/account/avatar").status == 404
  end
end

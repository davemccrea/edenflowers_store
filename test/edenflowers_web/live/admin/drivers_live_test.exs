defmodule EdenflowersWeb.Admin.DriversLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Delivery.Driver

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn, admin: admin}
  end

  test "shows the empty state when there are no drivers", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/drivers")
    assert html =~ "No drivers yet"
    assert has_element?(view, "a[href='/admin/drivers/new']", "Add driver")
  end

  test "lists existing drivers", %{conn: conn} do
    driver = generate(driver(name: "Asko Mäkinen"))

    {:ok, view, html} = live(conn, ~p"/admin/drivers")
    assert html =~ "Asko Mäkinen"
    assert has_element?(view, "a[href='/admin/drivers/#{driver.id}/edit']", "Edit")
  end

  test "creates a driver on the new driver page", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(conn, ~p"/admin/drivers/new")

    assert has_element?(view, "#driver-name[autofocus]")
    assert has_element?(view, "a[href='/admin/drivers']", "Cancel")

    view
    |> form("form", form: %{name: "Liisa Virtanen", phone: "+358401112222", locale: "fi"})
    |> render_submit()

    flash = assert_redirect(view, ~p"/admin/drivers")
    assert flash["info"] == "Driver added."
    created = Driver.list!(actor: admin) |> Enum.find(&(&1.name == "Liisa Virtanen"))
    assert created.locale == "fi"
    assert is_binary(created.link_token)
  end

  test "edits a driver", %{conn: conn} do
    driver = generate(driver(name: "Old Name"))

    {:ok, view, _html} = live(conn, ~p"/admin/drivers/#{driver.id}/edit")

    view
    |> form("form", form: %{name: "New Name"})
    |> render_submit()

    flash = assert_redirect(view, ~p"/admin/drivers")
    assert flash["info"] == "Driver updated."
    assert {:ok, %{name: "New Name"}} = Ash.get(Driver, driver.id, actor: admin_actor())
  end

  test "redirects when editing an unknown driver", %{conn: conn} do
    unknown_id = Ash.UUID.generate()

    assert {:error, {:live_redirect, %{to: "/admin/drivers", flash: %{"error" => "Driver not found."}}}} =
             live(conn, ~p"/admin/drivers/#{unknown_id}/edit")
  end

  test "deactivates and reactivates a driver", %{conn: conn} do
    driver = generate(driver(name: "Toggle Me"))

    {:ok, view, _html} = live(conn, ~p"/admin/drivers")

    html =
      view
      |> element("button[phx-click=deactivate][phx-value-id='#{driver.id}']")
      |> render_click()

    assert html =~ "Inactive"

    html =
      view
      |> element("button[phx-click=activate][phx-value-id='#{driver.id}']")
      |> render_click()

    assert html =~ "Active"
  end

  test "deletes a driver", %{conn: conn} do
    driver = generate(driver(name: "Delete Me"))

    {:ok, view, _html} = live(conn, ~p"/admin/drivers")

    html =
      view
      |> element("button[phx-click=delete][phx-value-id='#{driver.id}']")
      |> render_click()

    assert html =~ "Driver deleted."
    refute html =~ "Delete Me"
    assert {:error, %Ash.Error.Invalid{}} = Ash.get(Driver, driver.id, actor: admin_actor())
  end

  test "regenerating the link invalidates the old token", %{conn: conn, admin: admin} do
    driver = generate(driver(name: "Rotate"))
    old_token = driver.link_token

    {:ok, view, _html} = live(conn, ~p"/admin/drivers")

    html =
      view
      |> element("button[phx-click=regenerate_token][phx-value-id='#{driver.id}']")
      |> render_click()

    assert html =~ "Link regenerated"
    assert {:ok, nil} = Driver.get_by_token(old_token, actor: admin)
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end

  defp admin_actor, do: %{admin: true}
end

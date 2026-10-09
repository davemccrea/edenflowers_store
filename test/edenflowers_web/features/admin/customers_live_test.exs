defmodule EdenflowersWeb.Admin.CustomersLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn}
  end

  describe "customer list" do
    test "lists only users with a placed order", %{conn: conn} do
      ada = customer("Ada Lovelace", "ada@example.com")
      placed_order(user_id: ada.id)
      grace = customer("Grace Hopper", "grace@example.com")
      generate(order(user_id: grace.id, state: :payment))
      customer("Newsletter Only", "news@example.com")

      {:ok, view, _html} = live(conn, ~p"/admin/customers")

      assert has_element?(view, "[data-item-id]", "Ada Lovelace")
      refute has_element?(view, "[data-item-id]", "Grace Hopper")
      refute has_element?(view, "[data-item-id]", "Newsletter Only")
      assert has_element?(view, ~s(nav a[aria-current="page"]), "Customers")
    end

    test "searches by email as well as name", %{conn: conn} do
      placed_order(user_id: customer("Ada Lovelace", "ada@example.com").id)
      placed_order(user_id: customer("Grace Hopper", "admiral@example.com").id)

      {:ok, view, _html} = live(conn, ~p"/admin/customers?search=admiral")

      assert has_element?(view, "[data-item-id]", "Grace Hopper")
      refute has_element?(view, "[data-item-id]", "Ada Lovelace")
    end
  end

  describe "customer detail" do
    test "shows the customer's placed orders and nobody else's", %{conn: conn} do
      ada = customer("Ada Lovelace", "ada@example.com")
      first = placed_order(user_id: ada.id, order_reference: "ADA001", paid: "40.00")
      second = placed_order(user_id: ada.id, order_reference: "ADA002", paid: "25.50")
      generate(order(user_id: ada.id, state: :payment, order_reference: "ADACART"))
      placed_order(user_id: customer("Grace Hopper", "grace@example.com").id, order_reference: "GRACE01")

      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")

      assert has_element?(view, "h1", "Ada Lovelace")
      assert has_element?(view, ~s([data-item-id="#{first.id}"]), "ADA001")
      assert has_element?(view, ~s([data-item-id="#{second.id}"]), "ADA002")
      refute has_element?(view, "[data-item-id]", "ADACART")
      refute has_element?(view, "[data-item-id]", "GRACE01")
      assert has_element?(view, "#customer-summary", "65.50")
    end

    test "counts only paid orders towards the total spent", %{conn: conn} do
      ada = customer("Ada Lovelace", "ada@example.com")
      placed_order(user_id: ada.id, paid: "40.00")
      placed_order(user_id: ada.id, paid: "99.00", refunded: true)

      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")

      assert has_element?(view, "#customer-summary", "40.00")
      refute has_element?(view, "#customer-summary", "139.00")
    end

    test "does not show cancelled unpaid orders as unpaid", %{conn: conn} do
      ada = customer("Ada Lovelace", "ada@example.com")
      order = placed_order(user_id: ada.id, fulfillment_status: :cancelled)

      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")

      refute has_element?(view, ~s([data-item-id="#{order.id}"]), "Unpaid")
    end

    test "redirects when the user has never placed an order", %{conn: conn} do
      lurker = customer("Newsletter Only", "news@example.com")

      assert {:error, {:live_redirect, %{to: "/admin/customers"}}} =
               live(conn, ~p"/admin/customers/#{lurker.id}")
    end
  end

  test "an order links through to its customer", %{conn: conn} do
    ada = customer("Ada Lovelace", "ada@example.com")
    order = placed_order(user_id: ada.id, fulfillment_date: Date.utc_today())

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s(#order-customer-link[href="/admin/customers/#{ada.id}"]))
  end

  defp customer(name, email) do
    Ash.Seed.seed!(Edenflowers.Accounts.User, %{name: name, email: email})
  end
end

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
      placed_order(ada)
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
      placed_order(customer("Ada Lovelace", "ada@example.com"))
      placed_order(customer("Grace Hopper", "admiral@example.com"))

      {:ok, view, _html} = live(conn, ~p"/admin/customers?search=admiral")

      assert has_element?(view, "[data-item-id]", "Grace Hopper")
      refute has_element?(view, "[data-item-id]", "Ada Lovelace")
    end
  end

  describe "customer detail" do
    test "shows the customer's placed orders and nobody else's", %{conn: conn} do
      ada = customer("Ada Lovelace", "ada@example.com")
      first = placed_order(ada, order_reference: "ADA001", payment_status: :paid, amount_paid: Decimal.new("40.00"))
      second = placed_order(ada, order_reference: "ADA002", payment_status: :paid, amount_paid: Decimal.new("25.50"))
      generate(order(user_id: ada.id, state: :payment, order_reference: "ADACART"))
      placed_order(customer("Grace Hopper", "grace@example.com"), order_reference: "GRACE01")

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
      placed_order(ada, payment_status: :paid, amount_paid: Decimal.new("40.00"))
      placed_order(ada, payment_status: :refunded, amount_paid: Decimal.new("99.00"))

      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")

      assert has_element?(view, "#customer-summary", "40.00")
      refute has_element?(view, "#customer-summary", "139.00")
    end

    test "redirects when the user has never placed an order", %{conn: conn} do
      lurker = customer("Newsletter Only", "news@example.com")

      assert {:error, {:live_redirect, %{to: "/admin/customers"}}} =
               live(conn, ~p"/admin/customers/#{lurker.id}")
    end
  end

  test "an order links through to its customer", %{conn: conn} do
    ada = customer("Ada Lovelace", "ada@example.com")
    order = placed_order(ada, fulfillment_date: Date.utc_today())

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s(#order-customer-link[href="/admin/customers/#{ada.id}"]))
  end

  defp customer(name, email) do
    Ash.Seed.seed!(Edenflowers.Accounts.User, %{name: name, email: email})
  end

  defp placed_order(user, attrs \\ []) do
    generate(
      order(
        [
          user_id: user.id,
          customer_name: user.name,
          customer_email: to_string(user.email),
          state: :placed,
          ordered_at: DateTime.utc_now(),
          locale: "en-GB"
        ] ++ attrs
      )
    )
  end
end

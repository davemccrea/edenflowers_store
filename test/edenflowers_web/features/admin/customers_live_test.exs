defmodule EdenflowersWeb.Admin.CustomersLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Orders
  alias EdenflowersWeb.QueryCounter

  setup :log_in_admin

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

    test "order changes preserve the customer search", %{conn: conn, admin: admin} do
      order = placed_order(user_id: customer("Ada Lovelace", "ada@example.com").id)
      placed_order(user_id: customer("Grace Hopper", "grace@example.com").id)
      {:ok, view, _html} = live(conn, ~p"/admin/customers?search=Ada")
      render_async(view)

      reads = QueryCounter.track(view.pid)

      Orders.update_florist_note!(order, %{florist_note: "White flowers"}, actor: admin)
      eventually(fn -> assert QueryCounter.count(reads) > 0 end)
      render_async(view)

      assert has_element?(view, "[data-item-id]", "Ada Lovelace")
      refute has_element?(view, "[data-item-id]", "Grace Hopper")
    end

    test "payments and refunds preserve searching, spending order and pagination", %{conn: conn, admin: admin} do
      for amount <- 1..10 do
        user = customer("Sorted #{amount}", "sorted#{amount}@example.com")
        placed_order(user_id: user.id, paid: "#{amount}.00")
      end

      target = customer("Sorted Target", "target@example.com")
      order = placed_order(user_id: target.id, payment_intent_id: nil)
      placed_order(user_id: customer("Excluded", "excluded@example.com").id, paid: "80.00")

      {:ok, view, _html} =
        live(conn, ~p"/admin/customers?#{%{search: "Sorted", sort: "-total_spent", page_size: 10}}")

      render_async(view)
      refute has_element?(view, ~s([data-item-id="#{target.id}"]))
      refute has_element?(view, "[data-item-id]", "Excluded")
      assert has_element?(view, ~s([data-key="pagination_info_class"]), "showing 1-10 of 11")

      {:ok, paid} = Orders.record_payment(order, order.grand_total, :cash, actor: admin)

      eventually(fn -> assert render_async(view) =~ ~r/Sorted Target.*Sorted 10/s end)
      refute has_element?(view, "[data-item-id]", "Excluded")

      paid
      |> Ash.Changeset.for_update(
        :refund,
        %{amount: order.grand_total, payment_method: :cash, email_customer?: false},
        actor: admin
      )
      |> Ash.update!()

      eventually(fn ->
        render_async(view)
        refute has_element?(view, ~s([data-item-id="#{target.id}"]))
      end)

      view |> element(~s(button[title="Next page"])) |> render_click()
      render_async(view)

      assert has_element?(view, ~s([data-item-id="#{target.id}"]), "0,00")
      assert has_element?(view, ~s([data-key="pagination_info_class"]), "showing 11-11 of 11")
      refute has_element?(view, "[data-item-id]", "Excluded")
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
      assert has_element?(view, "#customer-summary", "65,50")
    end

    test "counts only paid orders towards the total spent", %{conn: conn} do
      ada = customer("Ada Lovelace", "ada@example.com")
      placed_order(user_id: ada.id, paid: "40.00")
      placed_order(user_id: ada.id, paid: "99.00", refunded: true)

      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")

      assert has_element?(view, "#customer-summary", "40,00")
      refute has_element?(view, "#customer-summary", "139,00")
    end

    test "external payments only change the customer summary after reload", %{conn: conn, admin: admin} do
      ada = customer("Ada Lovelace", "ada@example.com")
      order = placed_order(user_id: ada.id, payment_intent_id: nil)
      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")
      assert has_element?(view, "#customer-summary", "0,00")

      {:ok, paid} = Orders.record_payment(order, order.grand_total, :cash, actor: admin)

      assert has_element?(view, "#editor-stale-notice")
      assert has_element?(view, "#customer-summary", "0,00")
      {:ok, view, _} = live(conn, ~p"/admin/customers/#{ada.id}")
      assert has_element?(view, "#customer-summary", "88,50")
      assert has_element?(view, ~s([data-item-id="#{order.id}"]), "Paid")

      paid
      |> Ash.Changeset.for_update(:refund, %{amount: "10.00", payment_method: :cash, email_customer?: false},
        actor: admin
      )
      |> Ash.update!()

      assert has_element?(view, "#editor-stale-notice")
      assert has_element?(view, "#customer-summary", "88,50")
      {:ok, view, _} = live(conn, ~p"/admin/customers/#{ada.id}")
      assert has_element?(view, "#customer-summary", "78,50")
    end

    test "collection notifications do not mix another customer's records into the page", %{conn: conn, admin: admin} do
      ada = customer("Ada Lovelace", "ada@example.com")
      grace = customer("Grace Hopper", "grace@example.com")
      placed_order(user_id: ada.id)
      other_order = placed_order(user_id: grace.id)
      other_subscription = generate(subscription(user_id: grace.id))
      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")
      render_async(view)

      {:ok, _order} = Orders.update_florist_note(other_order, %{florist_note: "White flowers"}, actor: admin)
      {:ok, _subscription} = Orders.pause_subscription(other_subscription, actor: admin)
      render_async(view)

      assert has_element?(view, "#editor-stale-notice")
      assert has_element?(view, "h1", "Ada Lovelace")
      refute has_element?(view, ~s([data-item-id="#{other_order.id}"]))
      refute has_element?(view, ~s([data-item-id="#{other_subscription.id}"]))
    end

    test "does not show cancelled unpaid orders as unpaid", %{conn: conn} do
      ada = customer("Ada Lovelace", "ada@example.com")
      order = placed_order(user_id: ada.id, fulfillment_status: :cancelled)

      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")

      refute has_element?(view, ~s([data-item-id="#{order.id}"]), "Unpaid")
    end

    test "shows the customer's subscriptions and nobody else's", %{conn: conn} do
      ada = customer("Ada Lovelace", "ada@example.com")
      placed_order(user_id: ada.id)
      mine = generate(subscription(user_id: ada.id))
      theirs = generate(subscription(user_id: customer("Grace Hopper", "grace@example.com").id))

      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")

      assert has_element?(view, ~s([data-item-id="#{mine.id}"]))
      refute has_element?(view, ~s([data-item-id="#{theirs.id}"]))
    end

    test "an order edit flags the open customer as stale but no longer renames the account", %{conn: conn, admin: admin} do
      ada = customer("Ada Lovelace", "ada@example.com")

      order =
        placed_order(
          user_id: ada.id,
          customer_email: to_string(ada.email),
          payment_intent_id: nil,
          fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 1)
        )

      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")
      order = Orders.get_order_for_admin!(order.id, actor: admin)

      {:ok, _order} =
        Orders.edit_order(
          order,
          %{
            customer_name: "Ada Byron",
            line_items: Enum.map(order.line_items, &%{id: &1.id, quantity: &1.quantity})
          },
          actor: admin
        )

      render_async(view)
      assert has_element?(view, "#editor-stale-notice")
      assert has_element?(view, "h1", "Ada Lovelace")
      {:ok, view, _} = live(conn, ~p"/admin/customers/#{ada.id}")
      assert has_element?(view, "h1", "Ada Lovelace")
    end

    test "both owners keep their saved snapshot until reload when an order moves", %{conn: conn, admin: admin} do
      ada = customer("Ada Lovelace", "ada@example.com")
      grace = customer("Grace Hopper", "grace@example.com")

      moving =
        placed_order(
          user_id: ada.id,
          customer_email: to_string(ada.email),
          paid: "40.00",
          payment_intent_id: nil,
          fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 1)
        )

      placed_order(user_id: grace.id, paid: "10.00")
      {:ok, from_view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")
      {:ok, to_view, _html} = live(conn, ~p"/admin/customers/#{grace.id}")
      moving = Orders.get_order_for_admin!(moving.id, actor: admin)

      {:ok, _order} =
        Orders.edit_order(
          moving,
          %{
            customer_email: to_string(grace.email),
            customer_name: grace.name,
            line_items: Enum.map(moving.line_items, &%{id: &1.id, quantity: &1.quantity})
          },
          actor: admin
        )

      render_async(from_view)
      render_async(to_view)

      assert has_element?(from_view, "#editor-stale-notice")
      assert has_element?(to_view, "#editor-stale-notice")
      assert has_element?(from_view, ~s([data-item-id="#{moving.id}"]))
      refute has_element?(to_view, ~s([data-item-id="#{moving.id}"]))

      assert {:error, {:live_redirect, %{to: "/admin/customers"}}} =
               live(conn, ~p"/admin/customers/#{ada.id}")

      {:ok, to_view, _} = live(conn, ~p"/admin/customers/#{grace.id}")

      assert has_element?(to_view, ~s([data-item-id="#{moving.id}"]))
      assert has_element?(to_view, "#customer-summary", "50,00")
    end

    test "owned subscriptions only change after reloading the customer", %{conn: conn, admin: admin} do
      ada = customer("Ada Lovelace", "ada@example.com")
      placed_order(user_id: ada.id)
      mine = generate(subscription(user_id: ada.id))
      {:ok, view, _html} = live(conn, ~p"/admin/customers/#{ada.id}")

      {:ok, _paused} = Orders.pause_subscription(mine, actor: admin)
      render_async(view)

      assert has_element?(view, "#editor-stale-notice")
      assert has_element?(view, ~s([data-item-id="#{mine.id}"]), "Active")
      {:ok, view, _} = live(conn, ~p"/admin/customers/#{ada.id}")
      assert has_element?(view, ~s([data-item-id="#{mine.id}"]), "Paused")
    end

    test "redirects when the user has never placed an order", %{conn: conn} do
      lurker = customer("Newsletter Only", "news@example.com")

      assert {:error, {:live_redirect, %{to: "/admin/customers"}}} =
               live(conn, ~p"/admin/customers/#{lurker.id}")
    end
  end

  test "an order links through to its customer", %{conn: conn} do
    ada = customer("Ada Lovelace", "ada@example.com")
    order = placed_order(user_id: ada.id, fulfillment_date: Edenflowers.ShopTime.today())

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s(#order-customer-link[href="/admin/customers/#{ada.id}"]))
  end

  defp customer(name, email) do
    [local, domain] = String.split(email, "@")
    email = "#{local}+#{System.unique_integer([:positive])}@#{domain}"

    Ash.Seed.seed!(Edenflowers.Accounts.User, %{name: name, email: email})
  end
end

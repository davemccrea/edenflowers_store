defmodule EdenflowersWeb.Checkout.OrderLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Orders

  setup %{conn: conn} do
    user = generate(admin_user(admin: false)) |> with_token()

    conn = log_in(conn, user)

    %{conn: conn, user: user}
  end

  test "shows a placed order to its owner", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, paid: true)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")

    assert has_element?(view, "h1", "Thank you, Ada.")
    assert has_element?(view, "#order-status", "ready to collect")
    refute has_element?(view, "#order-status", "text message")
    assert has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)
  end

  test "counts a placed order once in Umami, with its revenue", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, paid: true)
    order_key = "order:#{order.id}"
    {:ok, %{grand_total: grand_total}} = Ash.load(order, :grand_total, authorize?: false)
    revenue = Decimal.to_float(grand_total)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")

    assert_push_event(view, "umami", %{
      name: "Order completed",
      data: %{revenue: ^revenue, currency: "EUR", subscription: false},
      once: ^order_key
    })
  end

  test "does not offer a receipt for an unpaid custom order", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, origin: :custom)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")

    refute has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)
    assert conn |> get(~p"/order/#{order.id}/receipt") |> response(404)
  end

  test "does not offer a receipt for a fully refunded order", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, refunded: true)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")

    refute has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)
  end

  test "says a text will follow when a pickup order has a phone number", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, customer_phone_number: "045 1505141", paid: true)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")

    assert has_element?(view, "#order-status", "I'll send a text message when it's ready.")
  end

  test "says a subscription carries on until it is changed", %{conn: conn, user: user} do
    order =
      generate(
        order(
          state: :placed,
          user_id: user.id,
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_method: :delivery,
          fulfillment_date: ~D[2026-06-10],
          locale: "en-GB"
        )
      )

    variant = generate(product_variant(product_id: generate(product(subscribable: true, free_delivery: true)).id))
    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1, interval_weeks: 2))

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")

    assert has_element?(view, "[data-testid=order-subscription]", "Every 2 weeks")

    next = Edenflowers.Format.weekday_date(~D[2026-06-24], "en-GB")
    charged = Edenflowers.Format.weekday_date(~D[2026-06-22], "en-GB")
    assert has_element?(view, "[data-testid=order-next-delivery]", next)
    assert has_element?(view, "[data-testid=order-next-charge]", "on #{charged}")
    assert has_element?(view, "[data-testid=manage-subscription]", "Manage subscription")
  end

  test "once the subscription starts, quotes what it charges, not the first order's waived fee", %{
    conn: conn,
    user: user
  } do
    delivery = generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :dynamic, base_price: "4.50"))
    variant = generate(product_variant(product_id: generate(product(subscribable: true)).id, price: "60.00"))

    subscription =
      generate(subscription(user_id: user.id, product_variant_id: variant.id, fulfillment_option_id: delivery.id))

    order =
      generate(
        order(
          state: :placed,
          origin: :online,
          user_id: user.id,
          subscription_id: subscription.id,
          fulfillment_option_id: delivery.id,
          fulfillment_method: :delivery,
          fulfillment_date: ~D[2026-06-10],
          distance: 3000,
          fulfillment_fee_override: "0.00",
          quoted_fulfillment_fee: "0.00",
          locale: "en-GB"
        )
      )

    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1, interval_weeks: 2))
    price = Ash.load!(subscription, :price_per_order, authorize?: false).price_per_order
    assert Decimal.gt?(price, "60.00")

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")

    assert has_element?(view, "[data-testid=order-next-charge]", Edenflowers.Format.currency(price, "en-GB"))
  end

  test "once the subscription starts, shows its own next delivery, that it's paused, or nothing once cancelled", %{
    conn: conn,
    user: user
  } do
    order =
      generate(
        order(
          state: :placed,
          user_id: user.id,
          fulfillment_method: :delivery,
          fulfillment_date: ~D[2026-06-10],
          locale: "en-GB"
        )
      )

    variant = generate(product_variant(product_id: generate(product(subscribable: true)).id))
    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1, interval_weeks: 2))

    subscription =
      generate(
        subscription(
          user_id: user.id,
          product_variant_id: variant.id,
          interval_weeks: 4,
          next_fulfillment_date: ~D[2026-07-15]
        )
      )

    Ash.Seed.update!(order, %{subscription_id: subscription.id})

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
    assert has_element?(view, "[data-testid=order-subscription]", "Every 4 weeks")

    assert has_element?(
             view,
             "[data-testid=order-next-delivery]",
             Edenflowers.Format.weekday_date(~D[2026-07-15], "en-GB")
           )

    assert has_element?(
             view,
             "[data-testid=order-next-charge]",
             "on #{Edenflowers.Format.weekday_date(~D[2026-07-13], "en-GB")}"
           )

    Ash.Seed.update!(subscription, %{state: :paused})
    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
    assert has_element?(view, "[data-testid=order-subscription]", "Every 4 weeks")
    assert has_element?(view, "[data-testid=order-next-delivery]", "Paused")
    refute has_element?(view, "[data-testid=order-next-charge]")

    Ash.Seed.update!(subscription, %{state: :cancelled})
    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
    refute has_element?(view, "[data-testid=order-subscription]")
  end

  test "says nothing about a subscription for a one-off order", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, paid: true)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")

    refute has_element?(view, "[data-testid=order-subscription]")
  end

  test "hides another customer's order", %{conn: conn} do
    other = generate(admin_user(admin: false))
    order = placed_order(user_id: other.id, paid: true)

    assert {:error, {:live_redirect, %{to: "/en"}}} = live(conn, ~p"/order/#{order.id}")
    assert conn |> get(~p"/order/#{order.id}/receipt") |> response(404)
    assert conn |> get(~p"/order/#{order.id}/pickup.ics") |> response(404)
  end

  test "shows the order while the webhook is still in flight, then confirms payment", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, state: :payment, ordered_at: nil)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
    assert has_element?(view, "h1", "Thank you, Ada.")
    refute has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)

    Orders.finalize_checkout!(order, order.payment_intent_id, %{amount_paid: "88.50"},
      actor: Edenflowers.Actors.system_actor()
    )

    assert has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)
  end

  test "does not let another customer wait on an order in payment", %{conn: conn} do
    other = generate(admin_user(admin: false))
    order = placed_order(user_id: other.id, state: :payment, ordered_at: nil)

    assert {:error, {:live_redirect, %{to: "/en"}}} = live(conn, ~p"/order/#{order.id}")
  end

  @tag :typst
  test "opens the receipt PDF inline", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, order_reference: "CONFIRM", paid: true)

    conn = get(conn, ~p"/order/#{order.id}/receipt")

    assert "%PDF" <> _ = response(conn, 200)
    assert get_resp_header(conn, "content-disposition") == [~s|inline; filename="eden-flowers-CONFIRM.pdf"|]
  end

  test "offers a calendar event for a pickup", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, paid: true)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
    assert has_element?(view, ~s|a[href="/order/#{order.id}/pickup.ics"]|)

    ics = conn |> get(~p"/order/#{order.id}/pickup.ics") |> response(200)
    assert ics =~ "DTSTART;VALUE=DATE:20260610\r\n"
    assert ics =~ "DTEND;VALUE=DATE:20260611\r\n"
    assert ics =~ "LOCATION:Muurahaistie 1\\, 65230 Vaasa"
  end

  test "offers no calendar event for a delivery", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, fulfillment_method: :delivery, paid: true)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
    refute has_element?(view, "[data-testid=add-to-calendar]")
    assert conn |> get(~p"/order/#{order.id}/pickup.ics") |> response(404)
  end

  describe "guest" do
    setup do
      %{
        conn:
          Phoenix.ConnTest.build_conn() |> put_req_header("accept-language", "en") |> Plug.Test.init_test_session(%{})
      }
    end

    test "sees their order when the webhook placed it before Stripe's redirect", %{conn: conn} do
      order = placed_order(paid: true)

      conn = conn |> with_cart(order) |> get(~p"/checkout/complete/#{order.id}")
      assert redirected_to(conn) == ~p"/order/#{order.id}"
      assert browser_cart(conn) == nil

      {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
      assert has_element?(view, "h1", "Thank you")
    end

    test "waits for the webhook when Stripe's redirect arrives first", %{conn: conn} do
      order = placed_order(state: :payment, ordered_at: nil)

      conn = conn |> with_cart(order) |> get(~p"/checkout/complete/#{order.id}")
      assert browser_cart(conn) == nil

      {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
      assert has_element?(view, "h1", "Thank you")
      refute has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)

      Orders.finalize_checkout!(order, order.payment_intent_id, %{amount_paid: "88.50"},
        actor: Edenflowers.Actors.system_actor()
      )

      assert has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)
    end

    test "sees the gift voucher they bought instead of a message card", %{conn: conn} do
      sale = paid_voucher_sale(%{card_message: "Yours, always"})

      conn = Plug.Test.init_test_session(conn, %{guest_order_id: sale.id})
      {:ok, view, _html} = live(conn, ~p"/order/#{sale.id}")

      # Typst takes longer than render_async's default 100 ms under a full test run.
      assert render_async(view, 5_000) =~ ~s|alt="Preview of your gift voucher"|
      refute has_element?(view, "[data-testid=order-card]")
    end

    test "goes back to checkout, keeping their cart, when a redirect payment fails", %{conn: conn} do
      order = placed_order(state: :payment, ordered_at: nil)

      conn =
        conn
        |> with_cart(order)
        |> get(~p"/checkout/complete/#{order.id}?redirect_status=failed")

      assert redirected_to(conn) == ~p"/checkout"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "didn't go through"
      assert browser_cart(conn).id == order.id
      assert Ash.reload!(order, authorize?: false).state == :payment
    end

    test "is sent to sign in for an order that wasn't their cart, keeping their cart", %{conn: conn} do
      order = placed_order(paid: true)
      cart = generate(order())

      conn = conn |> with_cart(cart) |> get(~p"/checkout/complete/#{order.id}")
      assert browser_cart(conn).id == cart.id

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/order/#{order.id}")
      assert to =~ "/sign-in?return_to="
      assert conn |> get(~p"/order/#{order.id}/receipt") |> response(404)
    end
  end

  defp paid_voucher_sale(attrs) do
    sale =
      Orders.start_gift_voucher_sale!(
        50,
        Map.merge(
          %{
            customer_name: "Anna Buyer",
            customer_email: "anna@example.com",
            recipient_name: "Mia",
            voucher_locale: "en-GB"
          },
          attrs
        ),
        actor: nil
      )

    Mox.expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn 5000, _metadata, nil ->
      {:ok, %{id: "pi_#{sale.id}", client_secret: "pi_secret", amount: 5000}}
    end)

    {:ok, _} = Orders.prepare_checkout_payment(sale.id, actor: nil)

    {:ok, :completed} =
      Edenflowers.Payments.complete(%{
        id: "pi_#{sale.id}",
        status: "succeeded",
        metadata: %{"order_id" => sale.id},
        amount_received: 5000
      })

    sale
  end

  defp browser_cart(conn), do: Orders.get_storefront_cart!(get_session(conn, :visitor_id), authorize?: false)
end

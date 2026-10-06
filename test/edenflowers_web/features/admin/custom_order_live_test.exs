defmodule EdenflowersWeb.Admin.CustomOrderLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Mox
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders

  setup :verify_on_exit!

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    tax_rate = generate(tax_rate(name: "Flowers"))
    product = generate(product(tax_rate_id: tax_rate.id, name: "Spring Bouquet"))
    variant = generate(product_variant(product_id: product.id, price: "49.00"))

    pickup =
      generate(fulfillment_option(tax_rate_id: tax_rate.id, name: "Pickup at the shop", base_price: "0.00"))

    %{conn: conn, admin: admin, tax_rate: tax_rate, variant: variant, pickup: pickup}
  end

  defp delivery_option(ctx) do
    generate(
      fulfillment_option(
        tax_rate_id: ctx.tax_rate.id,
        name: "Delivery",
        fulfillment_method: :delivery,
        rate_type: :dynamic,
        base_price: "5.00",
        price_per_km: "1.00",
        free_dist_km: 0,
        max_dist_km: 20
      )
    )
  end

  defp stub_geocoding(distance_m) do
    stub(Edenflowers.External.HereAPI.Mock, :geocode, fn _query ->
      {:ok, {"Kyrkvägen 5, Vasa", "63.09,21.61", "here:1"}}
    end)

    stub(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, distance_m} end)
  end

  defp tomorrow, do: Date.add(DateTime.now!("Europe/Helsinki") |> DateTime.to_date(), 1)

  defp place_custom_order(ctx, overrides \\ %{}) do
    {:ok, order} =
      Orders.place_custom_order(
        Map.merge(
          %{
            customer_name: "Mrs Holm",
            customer_phone_number: "040 123 4567",
            fulfillment_option_id: ctx.pickup.id,
            fulfillment_date: tomorrow(),
            locale: "en-GB",
            email_customer?: false,
            line_items: [
              %{
                "kind" => "custom",
                "description" => "Funeral spray",
                "unit_price" => "85.00",
                "tax_rate_id" => ctx.tax_rate.id,
                "quantity" => "1"
              }
            ]
          },
          overrides
        ),
        actor: ctx.admin
      )

    order
  end

  describe "placing a custom order" do
    test "Jennie enters the order and lands on its page", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      render_click(view, "add_line", %{"kind" => "catalogue"})
      render_click(view, "add_line", %{"kind" => "custom"})

      assert {:error, {:live_redirect, %{to: "/admin/orders/" <> id}}} =
               view
               |> form("#order-form",
                 form: %{
                   customer_name: "Mrs Holm",
                   customer_phone_number: "040 123 4567",
                   locale: "sv-FI",
                   fulfillment_option_id: ctx.pickup.id,
                   fulfillment_date: Date.to_iso8601(tomorrow()),
                   florist_note: "White only, no lilies",
                   line_items: %{
                     "0" => %{"product_variant_id" => ctx.variant.id, "quantity" => "1"},
                     "1" => %{
                       "description" => "Funeral spray",
                       "unit_price" => "85,50",
                       "tax_rate_id" => ctx.tax_rate.id,
                       "quantity" => "1"
                     }
                   }
                 }
               )
               |> render_submit()

      order = Orders.get_order_for_admin!(id, actor: ctx.admin)

      assert order.origin == :custom
      assert order.florist_note == "White only, no lilies"
      assert Decimal.equal?(order.grand_total, "134.50")
      assert order.payment_link_open?
    end

    test "warns about a closed day without refusing it", ctx do
      Ash.Seed.update!(ctx.pickup, %{available_days: []})

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      view
      |> form("#order-form",
        form: %{fulfillment_option_id: ctx.pickup.id, fulfillment_date: Date.to_iso8601(tomorrow())}
      )
      |> render_change()

      assert has_element?(view, "#date-warning", "normally closed")
    end

    test "prices the delivery as soon as the address is entered", ctx do
      delivery = delivery_option(ctx)
      stub_geocoding(8_000)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      view |> form("#order-form", form: %{fulfillment_option_id: delivery.id}) |> render_change()
      view |> form("#order-form", form: %{delivery_address: "Kyrkvägen 5"}) |> render_change()

      view |> element("#form_delivery_address") |> render_blur(%{"value" => "Kyrkvägen 5"})

      assert render_async(view) =~ "8.0 km"
      assert has_element?(view, "#delivery-quote", "13.00")
    end

    test "says when an address can't be delivered to", ctx do
      delivery = delivery_option(ctx)
      stub_geocoding(50_000)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      view |> form("#order-form", form: %{fulfillment_option_id: delivery.id}) |> render_change()
      view |> form("#order-form", form: %{delivery_address: "Far away 1"}) |> render_change()

      view |> element("#form_delivery_address") |> render_blur(%{"value" => "Far away 1"})
      render_async(view)

      assert has_element?(view, "#delivery-quote", "Outside delivery range")
      assert has_element?(view, "#delivery-quote", "You can still set your own fee")
    end

    test "shows a line's problem inside that line, after saving", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")
      render_click(view, "add_line", %{"kind" => "custom"})

      view
      |> form("#order-form",
        form: %{
          customer_name: "Mrs Holm",
          line_items: %{"0" => %{"description" => "Spray", "unit_price" => "lots", "quantity" => "1"}}
        }
      )
      |> render_submit()

      assert has_element?(view, "#line-0-error", "enter a price")
      assert has_element?(view, ~s|input[name="form[line_items][0][unit_price]"][aria-invalid="true"]|)
      assert has_element?(view, ~s|button[aria-label="Remove item 1"]|)
    end

    test "keeps quiet about missing items until Jennie tries to save", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      html = view |> form("#order-form", form: %{customer_name: "Mrs Holm"}) |> render_change()

      refute html =~ "Add at least one item"
    end

    test "shows what is missing instead of saving", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      html =
        view
        |> form("#order-form", form: %{customer_name: "Mrs Holm"})
        |> render_submit()

      assert html =~ "Add at least one item"
      assert html =~ "enter a phone number or an email"
    end
  end

  describe "editing" do
    test "an unpaid custom order opens in the full form", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}/edit")

      assert has_element?(view, "[data-testid=order-line]")

      assert {:error, {:live_redirect, _}} =
               view
               |> form("#order-form",
                 form: %{
                   line_items: %{
                     "0" => %{
                       "description" => "Funeral spray, larger",
                       "unit_price" => "120.00",
                       "tax_rate_id" => ctx.tax_rate.id,
                       "quantity" => "1"
                     }
                   }
                 }
               )
               |> render_submit()

      assert Decimal.equal?(Orders.get_order_for_admin!(order.id, actor: ctx.admin).grand_total, "120.00")
    end

    test "a paid order can change too, and its page shows what is left to collect", ctx do
      order = place_custom_order(ctx)
      {:ok, order} = Orders.record_in_person_payment(order, "85.00", :zettle, actor: ctx.admin)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}/edit")

      assert {:error, {:live_redirect, _}} =
               view
               |> form("#order-form",
                 form: %{
                   line_items: %{
                     "0" => %{
                       "description" => "Funeral spray",
                       "unit_price" => "95.00",
                       "tax_rate_id" => ctx.tax_rate.id,
                       "quantity" => "1"
                     }
                   }
                 }
               )
               |> render_submit()

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      assert has_element?(view, "#order-payment-summary", "To collect")
      assert has_element?(view, ~s|#in-person-payment-form input[value="10.00"]|)
    end
  end

  describe "the order page" do
    test "shows the payment link to copy while the order is unpaid", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      assert has_element?(view, ~s|#payment-link-url[value$="/pay/#{order.payment_link_token}"]|)
      assert has_element?(view, "header", "Unpaid")
    end

    test "records an in-person payment", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      view
      |> form("#in-person-payment-form", in_person: %{payment_method: "mobilepay", amount: "85,00"})
      |> render_submit()

      assert has_element?(view, "#order-payments", "MobilePay")
      refute has_element?(view, "#payment-link-url")
      refute has_element?(view, "#in-person-payment-form")
    end

    test "logs what happened to the order", ctx do
      order = place_custom_order(ctx)
      {:ok, _order} = Orders.record_in_person_payment(order, "85.00", :mobilepay, actor: ctx.admin)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      assert has_element?(view, "#order-log", "Placed by Jennie")
      assert has_element?(view, "#order-log", "1 × Funeral spray")
      assert has_element?(view, "#order-payments", "MobilePay")
    end

    test "saves the florist note", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      view
      |> form("#florist-note-form", note: %{florist_note: "Service at 11:00, deliver by 10:30"})
      |> render_submit()

      assert Orders.get_order_for_admin!(order.id, actor: ctx.admin).florist_note ==
               "Service at 11:00, deliver by 10:30"
    end

    test "cancels the order and closes its payment link", ctx do
      order = place_custom_order(ctx) |> Ash.Seed.update!(%{payment_intent_id: "pi_link"})
      expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_link"} -> {:ok, %{id: "pi_link"}} end)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      render_click(view, "cancel_order")

      assert has_element?(view, "header", "Cancelled")
      refute has_element?(view, "header", "Unpaid")
      refute has_element?(view, "#payment-link-url")
      refute has_element?(view, ~s|button[phx-click="mark_fulfilled"]|)
    end

    test "asks before fulfilling an unpaid order", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      assert has_element?(view, ~s|button[phx-click="mark_fulfilled"][data-confirm*="still unpaid"]|)
    end
  end
end

defmodule Edenflowers.Orders.CustomOrderTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.External.{HereAPI, StripeAPI}
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.{SendConfirmationEmail, SendOrderDetailsEmail}
  alias Edenflowers.Payments

  setup :verify_on_exit!

  setup do
    tax_rate = generate(tax_rate(percentage: "0.255"))
    product = generate(product(tax_rate_id: tax_rate.id, name: "Spring Bouquet"))
    variant = generate(product_variant(product_id: product.id, price: "49.00"))

    pickup =
      generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :pickup, base_price: "0.00"))

    delivery =
      generate(
        fulfillment_option(
          tax_rate_id: tax_rate.id,
          fulfillment_method: :delivery,
          rate_type: :dynamic,
          base_price: "5.00",
          price_per_km: "1.00",
          free_dist_km: 0,
          max_dist_km: 20
        )
      )

    %{admin: generate(admin_user()), tax_rate: tax_rate, variant: variant, pickup: pickup, delivery: delivery}
  end

  defp tomorrow, do: Date.add(DateTime.now!("Europe/Helsinki") |> DateTime.to_date(), 1)

  defp custom_line(tax_rate, attrs \\ %{}) do
    Map.merge(
      %{
        "kind" => "custom",
        "description" => "Funeral spray",
        "unit_price" => "85,00",
        "tax_rate_id" => tax_rate.id,
        "quantity" => "1"
      },
      attrs
    )
  end

  defp catalogue_line(variant, quantity \\ "1") do
    %{"kind" => "catalogue", "product_variant_id" => variant.id, "quantity" => quantity}
  end

  defp params(ctx, overrides \\ %{}) do
    Map.merge(
      %{
        customer_name: "Mrs Holm",
        customer_phone_number: "040 123 4567",
        locale: "sv-FI",
        fulfillment_option_id: ctx.pickup.id,
        fulfillment_date: tomorrow(),
        line_items: [catalogue_line(ctx.variant), custom_line(ctx.tax_rate)]
      },
      overrides
    )
  end

  defp place(ctx, overrides \\ %{}) do
    Orders.place_custom_order(params(ctx, overrides), actor: ctx.admin)
  end

  defp stub_geocoding(distance_m) do
    stub(HereAPI.Mock, :geocode, fn _query -> {:ok, {"Kyrkvägen 5, Vasa", "63.09,21.61", "here:1"}} end)
    stub(HereAPI.Mock, :route_distance, fn _position -> {:ok, distance_m} end)
  end

  describe "placing a custom order" do
    test "is placed straight away, unpaid, with its own reference", ctx do
      {:ok, order} = place(ctx)

      order = Ash.load!(order, [:grand_total, :unpaid?, :vat, line_items: [:subtotal]], authorize?: false)

      assert order.state == :placed
      assert order.origin == :custom
      assert order.payment_status == :pending
      assert order.unpaid?
      assert order.order_reference
      assert order.ordered_at
      assert Decimal.equal?(order.grand_total, "134.00")
      assert Enum.map(order.line_items, & &1.product_name) == ["Spring Bouquet", "Funeral spray"]
      assert [%{rate: rate}] = order.vat_breakdown
      assert Decimal.equal?(rate, "0.255")
      assert Decimal.equal?(order.vat, "27.23")
    end

    test "a custom item has no product behind it", ctx do
      {:ok, order} = place(ctx, %{line_items: [custom_line(ctx.tax_rate)]})

      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items

      assert line_item.product_id == nil
      assert line_item.product_variant_id == nil
      assert Decimal.equal?(line_item.unit_price, "85.00")
    end

    test "comes with a payment link unless the customer pays in person", ctx do
      {:ok, with_link} = place(ctx)
      {:ok, in_person} = place(ctx, %{payment_link?: false})

      assert is_binary(with_link.payment_link_token)
      assert in_person.payment_link_token == nil
    end

    test "needs a phone number or an email", ctx do
      assert {:error, error} = place(ctx, %{customer_phone_number: nil})
      assert Exception.message(error) =~ "enter a phone number or an email"

      assert {:ok, _order} = place(ctx, %{customer_phone_number: nil, customer_email: "son@example.com"})
    end

    test "with an email, links the order to that customer's account", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com"})

      assert order.user_id
      assert {:ok, user} = Edenflowers.Accounts.get_user_by_email("son@example.com", authorize?: false)
      assert user.id == order.user_id
    end

    test "without an email, no account is made", ctx do
      {:ok, order} = place(ctx)

      assert order.user_id == nil
    end

    test "carries a card message without a card in its lines", ctx do
      {:ok, order} = place(ctx, %{card_message: "With deepest sympathy"})

      assert order.card_message == "With deepest sympathy"

      assert {:error, error} = place(ctx, %{card_message: String.duplicate("a", 201)})
      assert Exception.message(error) =~ "at most 200 characters"
    end

    test "names a recipient only when the flowers are for somebody else", ctx do
      {:ok, for_herself} = place(ctx)
      {:ok, gift} = place(ctx, %{recipient_name: "St. Olof's church"})

      refute for_herself.gift
      assert gift.gift
    end

    test "may be booked on a closed day, but never in the past", ctx do
      closed = Ash.Seed.update!(ctx.pickup, %{available_days: []})

      assert {:ok, _order} = place(ctx, %{fulfillment_option_id: closed.id})

      assert {:error, error} = place(ctx, %{fulfillment_date: Date.add(tomorrow(), -2)})
      assert Exception.message(error) =~ "cannot be in the past"
    end

    test "needs at least one valid item", ctx do
      assert {:error, error} = place(ctx, %{line_items: []})
      assert Exception.message(error) =~ "Add at least one item"

      assert {:error, error} = place(ctx, %{line_items: [custom_line(ctx.tax_rate, %{"unit_price" => "lots"})]})
      assert Exception.message(error) =~ "Item 1: enter a price"
    end

    test "only Jennie can place one", ctx do
      {:ok, customer} = Edenflowers.Accounts.upsert_user("customer@example.com", "A Customer", authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} = Orders.place_custom_order(params(ctx), actor: customer)

      assert {:error, %Ash.Error.Forbidden{}} = Orders.place_custom_order(params(ctx), actor: nil)
    end

    test "queues the order details email when the customer has an email", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", payment_link?: true})

      assert_enqueued(worker: SendOrderDetailsEmail, args: %{"primary_key" => %{"id" => order.id}})

      Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.to == [{"", "son@example.com"}]
        assert email.text_body =~ "Funeral spray"
        assert email.text_body =~ "/pay/#{order.payment_link_token}"
      end)
    end

    test "sends nothing when Jennie chooses not to", ctx do
      {:ok, _order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})

      refute_enqueued(worker: SendOrderDetailsEmail)
    end
  end

  describe "the delivery fee" do
    test "is calculated from the address", ctx do
      stub_geocoding(8_000)

      {:ok, order} =
        place(ctx, %{
          fulfillment_option_id: ctx.delivery.id,
          delivery_address: "Kyrkvägen 5",
          recipient_phone_number: "040 765 4321"
        })

      assert Decimal.equal?(order.fulfillment_fee, "13.00")
      assert order.position == "63.09,21.61"
    end

    test "is Jennie's own when she sets one", ctx do
      stub_geocoding(8_000)

      {:ok, order} =
        place(ctx, %{
          fulfillment_option_id: ctx.delivery.id,
          delivery_address: "Kyrkvägen 5",
          recipient_phone_number: "040 765 4321",
          fulfillment_fee_override: "0"
        })

      assert Decimal.equal?(order.fulfillment_fee, "0")
    end

    test "outside the delivery range needs her own fee", ctx do
      stub_geocoding(50_000)

      delivery = %{
        fulfillment_option_id: ctx.delivery.id,
        delivery_address: "Far away 1",
        recipient_phone_number: "040 765 4321"
      }

      assert {:error, error} = place(ctx, delivery)
      assert Exception.message(error) =~ "Enter your own delivery fee"

      assert {:ok, order} = place(ctx, Map.put(delivery, :fulfillment_fee_override, "25.00"))
      assert Decimal.equal?(order.fulfillment_fee, "25.00")
    end
  end

  describe "editing" do
    test "an unpaid custom order can change its items and price", ctx do
      {:ok, order} = place(ctx)

      {:ok, order} =
        Orders.update_custom_order(order, params(ctx, %{line_items: [catalogue_line(ctx.variant, "2")]}),
          actor: ctx.admin
        )

      order = Ash.load!(order, [:grand_total, :line_items], authorize?: false)

      assert [%{quantity: 2}] = order.line_items
      assert Decimal.equal?(order.grand_total, "98.00")
      assert [%{gross: gross}] = order.vat_breakdown
      assert Decimal.equal?(gross, "98.00")
    end

    test "a paid order can't change its items", ctx do
      {:ok, order} = place(ctx)

      {:ok, order} =
        Orders.record_in_person_payment(order, %{payment_method: :zettle, amount_paid: "134.00"}, actor: ctx.admin)

      assert {:error, error} = Orders.update_custom_order(order, params(ctx), actor: ctx.admin)
      assert Exception.message(error) =~ "a paid order can't change its items or price"
    end

    test "a paid order can move to a new address and keep its fee", ctx do
      stub_geocoding(8_000)

      order =
        generate(
          order(
            state: :placed,
            payment_status: :paid,
            fulfillment_method: :delivery,
            fulfillment_option_id: ctx.delivery.id,
            fulfillment_date: tomorrow(),
            delivery_address: "Kyrkvägen 3",
            recipient_phone_number: "+358401234567",
            fulfillment_fee: Decimal.new("7.00")
          )
        )

      {:ok, order} = Orders.update_order_details(order, %{delivery_address: "Kyrkvägen 5"}, actor: ctx.admin)

      assert order.delivery_address == "Kyrkvägen 5"
      assert order.position == "63.09,21.61"
      assert Decimal.equal?(order.fulfillment_fee, "7.00")
    end

    test "the florist note can change on any order, even a fulfilled one", ctx do
      order = generate(order(state: :placed, payment_status: :paid, fulfillment_status: :fulfilled))

      {:ok, order} = Orders.update_florist_note(order, %{florist_note: "White only, no lilies"}, actor: ctx.admin)

      assert order.florist_note == "White only, no lilies"
    end
  end

  describe "cancelling" do
    test "takes the order off the list to fulfil and closes its payment link", ctx do
      {:ok, order} = place(ctx)
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})

      expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_link"} -> {:ok, %{id: "pi_link"}} end)

      {:ok, order} = Orders.cancel_order(order, actor: ctx.admin)

      assert order.fulfillment_status == :cancelled
      assert order.cancelled_at
      refute order.payment_link_open?
      refute order.id in Enum.map(Orders.list_orders_to_fulfil!(actor: ctx.admin), & &1.id)
    end

    test "Stripe cancelling the PaymentIntent doesn't mark the payment failed", ctx do
      {:ok, order} = place(ctx)
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})
      stub(StripeAPI.Mock, :cancel_payment_intent, fn intent -> {:ok, intent} end)
      {:ok, _order} = Orders.cancel_order(order, actor: ctx.admin)

      {:ok, _} = Payments.fail(%{id: "pi_link", metadata: %{"order_id" => order.id}})

      assert Orders.get_order_by_id!(order.id, authorize?: false).payment_status == :pending
    end
  end

  describe "paying" do
    test "an unpaid custom order is still on the list to fulfil", ctx do
      {:ok, order} = place(ctx)

      assert order.id in Enum.map(Orders.list_orders_to_fulfil!(actor: ctx.admin), & &1.id)
    end

    test "in person records how it was paid and sends no receipt by itself", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})

      {:ok, order} =
        Orders.record_in_person_payment(order, %{payment_method: :mobilepay, amount_paid: "130.00"}, actor: ctx.admin)

      assert order.payment_status == :paid
      assert order.payment_method == :mobilepay
      assert order.paid_at
      assert order.amount_mismatch?
      refute order.payment_link_open?

      Oban.drain_queue(queue: :default)
      refute_enqueued(worker: SendConfirmationEmail)
      assert_no_email_sent()
    end

    test "in person can't be recorded as a Stripe payment", ctx do
      {:ok, order} = place(ctx)

      assert {:error, _} =
               Orders.record_in_person_payment(order, %{payment_method: :stripe, amount_paid: "134.00"},
                 actor: ctx.admin
               )
    end

    test "through the payment link records the payment and emails the receipt", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})

      assert {:ok, :completed} =
               Payments.complete(%{
                 id: "pi_link",
                 metadata: %{"order_id" => order.id},
                 amount_received: 13_400
               })

      paid = Orders.get_order_by_id!(order.id, authorize?: false)

      assert paid.payment_status == :paid
      assert paid.payment_method == :stripe
      assert paid.state == :placed
      assert paid.order_reference == order.order_reference
      assert_enqueued(worker: SendConfirmationEmail, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "through the payment link after paying in person is reported as a double payment", ctx do
      {:ok, order} = place(ctx)
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})
      stub(StripeAPI.Mock, :cancel_payment_intent, fn _intent -> {:error, :already_succeeded} end)

      capture_log(fn ->
        {:ok, _order} =
          Orders.record_in_person_payment(order, %{payment_method: :zettle, amount_paid: "134.00"}, actor: ctx.admin)
      end)

      assert {:error, {:unexpected_payment, _id, "paid_in_person"}} =
               Payments.complete(%{id: "pi_link", metadata: %{"order_id" => order.id}, amount_received: 13_400})
    end
  end

  describe "emailing the receipt on request" do
    @tag :typst
    test "sends it for an order paid in person", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})

      {:ok, order} =
        Orders.record_in_person_payment(order, %{payment_method: :cash, amount_paid: "134.00"}, actor: ctx.admin)

      {:ok, order} = Orders.email_receipt(order, actor: ctx.admin)

      assert order.receipt_emailed_at
      assert_email_sent(fn email -> assert [_receipt] = email.attachments end)
    end

    test "refuses an unpaid order", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})

      assert {:error, error} = Orders.email_receipt(order, actor: ctx.admin)
      assert Exception.message(error) =~ "is not paid yet"
    end
  end
end

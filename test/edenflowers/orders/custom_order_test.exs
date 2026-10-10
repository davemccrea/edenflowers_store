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

      assert {:error, error} = place(ctx, %{line_items: [custom_line(ctx.tax_rate, %{"description" => "   "})]})
      assert Exception.message(error) =~ "Item 1: describe the item"
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

    test "sent again, shows the order as it now stands rather than thanking for it anew", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", locale: "en-GB"})
      Oban.drain_queue(queue: :default)
      assert_email_sent(fn email -> assert email.text_body =~ "Here is what we agreed" end)

      {:ok, _order} = Orders.send_order_details_email(order, actor: ctx.admin)

      assert_email_sent(fn email ->
        refute email.text_body =~ "Here is what we agreed"
        assert email.text_body =~ "Here is your order as it stands now"
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
    test "clearing the email removes the old customer's access", ctx do
      {:ok, order} = place(ctx, %{customer_email: "old@example.com"})
      old_user = Edenflowers.Accounts.get_user_by_email!("old@example.com", authorize?: false)

      {:ok, order} = Orders.edit_order(order, params(ctx, %{customer_email: nil}), actor: ctx.admin)

      assert order.user_id == nil
      assert Orders.list_my_orders!(actor: old_user) == []
    end

    test "a stale line id is a validation error", ctx do
      {:ok, order} = place(ctx)
      stale = %{"kind" => "catalogue", "id" => Ash.UUID.generate(), "quantity" => "1"}

      assert {:error, error} = Orders.edit_order(order, params(ctx, %{line_items: [stale]}), actor: ctx.admin)
      assert Exception.message(error) =~ "no longer available"
    end

    test "an unpaid custom order can change its items and price", ctx do
      {:ok, order} = place(ctx)

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{line_items: [catalogue_line(ctx.variant, "2")]}), actor: ctx.admin)

      order = Ash.load!(order, [:grand_total, :line_items], authorize?: false)

      assert [%{quantity: 2}] = order.line_items
      assert Decimal.equal?(order.grand_total, "98.00")
      assert [%{gross: gross}] = order.vat_breakdown
      assert Decimal.equal?(gross, "98.00")
    end

    test "a paid order can still change, leaving a balance to collect or refund", ctx do
      {:ok, order} = place(ctx)
      {:ok, order} = Orders.record_in_person_payment(order, "134.00", :zettle, actor: ctx.admin)

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{line_items: [catalogue_line(ctx.variant)]}), actor: ctx.admin)

      order = Ash.load!(order, [:balance], authorize?: false)
      assert Decimal.equal?(order.balance, "-85.00")

      {:ok, _order} = Orders.record_in_person_payment(order, "-85.00", :cash, actor: ctx.admin)
      assert Decimal.equal?(Orders.get_order_for_admin!(order.id, actor: ctx.admin).balance, "0.00")
    end

    test "records how an in-person payment was made, for the receipt", ctx do
      {:ok, order} = place(ctx)
      {:ok, order} = Orders.record_in_person_payment(order, "134.00", :zettle, actor: ctx.admin)

      assert [%{payment_method_type: "zettle", card_brand: nil}] =
               Ash.load!(order, :payments, authorize?: false).payments
    end

    test "a new delivery address is priced again", ctx do
      stub_geocoding(8_000)

      delivery = %{
        fulfillment_option_id: ctx.delivery.id,
        delivery_address: "Kyrkvägen 3",
        recipient_phone_number: "040 765 4321"
      }

      {:ok, order} = place(ctx, delivery)
      assert Decimal.equal?(order.fulfillment_fee, "13.00")

      stub_geocoding(12_000)

      {:ok, order} =
        Orders.edit_order(order, params(ctx, Map.put(delivery, :delivery_address, "Kyrkvägen 5")), actor: ctx.admin)

      assert Decimal.equal?(order.fulfillment_fee, "17.00")
    end

    test "an edit that leaves the address alone keeps the fee", ctx do
      stub_geocoding(8_000)

      delivery = %{
        fulfillment_option_id: ctx.delivery.id,
        delivery_address: "Kyrkvägen 3",
        recipient_phone_number: "040 765 4321"
      }

      {:ok, order} = place(ctx, delivery)
      Ash.Seed.update!(ctx.delivery, %{base_price: Decimal.new("9.00")})

      {:ok, order} = Orders.edit_order(order, params(ctx, Map.put(delivery, :card_message, "Hi")), actor: ctx.admin)

      assert Decimal.equal?(order.fulfillment_fee, "13.00")
    end

    test "the log shows a new address, not item changes, when only the address moves", ctx do
      stub_geocoding(8_000)

      delivery = %{
        fulfillment_option_id: ctx.delivery.id,
        delivery_address: "Kyrkvägen 3",
        recipient_phone_number: "040 765 4321",
        line_items: [catalogue_line(ctx.variant)]
      }

      {:ok, order} = place(ctx, delivery)
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      kept = [%{"kind" => "catalogue", "id" => line_item.id, "quantity" => "1"}]

      stub_geocoding(12_000)

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{delivery | delivery_address: "Kyrkvägen 5", line_items: kept}),
          actor: ctx.admin
        )

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      [edit | _placed] = EdenflowersWeb.Admin.OrderLog.entries(versions, [], "en-GB")

      assert edit.title == "Edited"
      assert {"Delivery address", "Kyrkvägen 5"} in edit.details
      assert {"Fulfillment fee", "€17.00"} in edit.details
      refute List.keymember?(edit.details, "Items", 0)
      assert length(EdenflowersWeb.Admin.OrderLog.entries(versions, [], "en-GB")) == 2
    end

    test "the log lists the items when they change", ctx do
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.variant)]})
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      kept = %{"kind" => "catalogue", "id" => line_item.id, "quantity" => "2"}

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{line_items: [kept, custom_line(ctx.tax_rate)]}), actor: ctx.admin)

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      [edit, placed] = EdenflowersWeb.Admin.OrderLog.entries(versions, [], "en-GB")

      assert {"Items", ["2 × Spring Bouquet", "1 × Funeral spray"]} in edit.details
      assert {"Items", ["1 × Spring Bouquet"]} in placed.details
    end

    test "the log names the language an edit switched to", ctx do
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.variant)]})
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      kept = %{"kind" => "catalogue", "id" => line_item.id, "quantity" => "1"}

      {:ok, order} = Orders.edit_order(order, params(ctx, %{locale: "fi", line_items: [kept]}), actor: ctx.admin)

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      [edit | _placed] = EdenflowersWeb.Admin.OrderLog.entries(versions, [], "en-GB")

      assert {"Language", "Suomi"} in edit.details
    end

    test "an edit that changes nothing leaves no entry in the log", ctx do
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.variant)]})
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      kept = %{"kind" => "catalogue", "id" => line_item.id, "quantity" => "1"}

      {:ok, order} = Orders.edit_order(order, params(ctx, %{line_items: [kept]}), actor: ctx.admin)

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      assert [%{title: "Placed by Jennie"}] = EdenflowersWeb.Admin.OrderLog.entries(versions, [], "en-GB")
    end

    test "a line the order already has keeps the price it was sold at", ctx do
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.variant)]})
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      Ash.Seed.update!(ctx.variant, %{price: Decimal.new("60.00")})

      kept = %{"kind" => "catalogue", "id" => line_item.id, "quantity" => "2"}
      {:ok, order} = Orders.edit_order(order, params(ctx, %{line_items: [kept]}), actor: ctx.admin)

      assert [%{id: id, quantity: 2, unit_price: price}] = Ash.load!(order, :line_items, authorize?: false).line_items
      assert id == line_item.id
      assert Decimal.equal?(price, "49.00")
    end

    test "an online order with a card keeps it as a card", ctx do
      card = generate(product_variant(product_id: generate(product(tax_rate_id: ctx.tax_rate.id)).id, price: "4.00"))

      order =
        generate(
          order(
            state: :placed,
            customer_name: "Ada",
            customer_email: "ada@example.com",
            fulfillment_option_id: ctx.pickup.id,
            fulfillment_method: :pickup,
            fulfillment_date: tomorrow(),
            card_message: "Happy birthday",
            locale: "en-GB"
          )
        )

      card_line = generate(line_item(order_id: order.id, product_variant_id: card.id, is_card: true))
      kept = %{"kind" => "catalogue", "id" => card_line.id, "quantity" => "1"}

      {:ok, order} =
        Orders.edit_order(
          order,
          %{
            customer_name: "Ada",
            fulfillment_option_id: ctx.pickup.id,
            fulfillment_date: tomorrow(),
            line_items: [kept, catalogue_line(ctx.variant)]
          },
          actor: ctx.admin
        )

      assert [%{is_card: true}, %{is_card: false}] = Ash.load!(order, :line_items, authorize?: false).line_items
    end

    test "the florist note can change on any order, even a fulfilled one", ctx do
      order = generate(order(state: :placed, fulfillment_status: :fulfilled))

      {:ok, order} = Orders.update_florist_note(order, %{florist_note: "White only, no lilies"}, actor: ctx.admin)

      assert order.florist_note == "White only, no lilies"

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      [change | _] = EdenflowersWeb.Admin.OrderLog.entries(versions, [], "en-GB")
      assert change.title == "Florist note changed"
      assert change.details == [{nil, "White only, no lilies"}]
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

    test "Stripe cancelling the PaymentIntent leaves a cancelled order alone", ctx do
      {:ok, order} = place(ctx)
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})
      stub(StripeAPI.Mock, :cancel_payment_intent, fn intent -> {:ok, intent} end)
      {:ok, _order} = Orders.cancel_order(order, actor: ctx.admin)

      {:ok, :unchanged} = Payments.cancel(%{id: "pi_link", metadata: %{"order_id" => order.id}})

      assert Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status]).payment_status == nil
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
        Orders.record_in_person_payment(order, "130.00", :mobilepay, actor: ctx.admin)

      order = Orders.get_order_for_admin!(order.id, actor: ctx.admin, load: [:payments])
      assert order.payment_status == :pending
      assert [%{method: :mobilepay, payment_intent_id: nil}] = order.payments
      assert Decimal.equal?(order.balance, "4.00")
      assert order.payment_link_open?

      Oban.drain_queue(queue: :default)
      refute_enqueued(worker: SendConfirmationEmail)
      assert_no_email_sent()
    end

    test "payment status follows the balance", ctx do
      {:ok, order} = place(ctx)

      {:ok, partial} = Orders.record_in_person_payment(order, "10.00", :cash, actor: ctx.admin)
      assert partial.payment_status == :pending

      {:ok, paid} = Orders.record_in_person_payment(partial, "124.00", :cash, actor: ctx.admin)
      assert paid.payment_status == :paid

      {:ok, refunded} = Orders.record_in_person_payment(paid, "-134.00", :cash, actor: ctx.admin)
      assert refunded.payment_status == :refunded
    end

    test "a free order owes nothing", ctx do
      {:ok, order} = place(ctx, %{line_items: [custom_line(ctx.tax_rate, %{"unit_price" => "0,00"})]})

      order = Ash.load!(order, [:unpaid?, :payable?], authorize?: false)
      assert order.payment_status == :paid
      refute order.unpaid?
      refute order.payable?
    end

    test "in person can't be recorded as a Stripe payment", ctx do
      {:ok, order} = place(ctx)

      assert {:error, _} =
               Orders.record_in_person_payment(order, "134.00", :stripe, actor: ctx.admin)
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

      paid = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payments, :payment_status])

      assert paid.payment_status == :paid
      assert [%{method: :stripe, payment_intent_id: "pi_link"}] = paid.payments
      assert paid.payment_intent_id == nil
      assert paid.state == :placed
      assert paid.order_reference == order.order_reference
      assert_enqueued(worker: SendConfirmationEmail, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "through the payment link after paying in person is still recorded, and reported to refund", ctx do
      {:ok, order} = place(ctx)
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})
      stub(StripeAPI.Mock, :cancel_payment_intent, fn _intent -> {:error, :already_succeeded} end)

      capture_log(fn ->
        {:ok, _order} =
          Orders.record_in_person_payment(order, "134.00", :zettle, actor: ctx.admin)
      end)

      log =
        capture_log(fn ->
          assert {:ok, :completed} =
                   Payments.complete(%{id: "pi_link", metadata: %{"order_id" => order.id}, amount_received: 13_400})
        end)

      assert log =~ "overpaid by 134.00"
      assert Decimal.equal?(Orders.get_order_for_admin!(order.id, actor: ctx.admin).balance, "-134.00")
    end

    test "a balance left by an edit can be paid through a new link payment", ctx do
      {:ok, order} = place(ctx, %{email_customer?: false})
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_first"})

      {:ok, :completed} =
        Payments.complete(%{id: "pi_first", metadata: %{"order_id" => order.id}, amount_received: 13_400})

      order = Orders.get_order_for_admin!(order.id, actor: ctx.admin)

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{line_items: [catalogue_line(ctx.variant, "3")]}), actor: ctx.admin)

      order = Orders.get_order_for_admin!(order.id, actor: ctx.admin)
      assert Decimal.equal?(order.balance, "13.00")
      assert order.payment_status == :pending
      assert order.payment_link_open?

      Ash.Seed.update!(order, %{payment_intent_id: "pi_top_up"})

      {:ok, :completed} =
        Payments.complete(%{id: "pi_top_up", metadata: %{"order_id" => order.id}, amount_received: 1300})

      order = Orders.get_order_for_admin!(order.id, actor: ctx.admin)
      assert Decimal.equal?(order.balance, "0.00")
      refute order.payment_link_open?
    end
  end

  describe "emailing the receipt on request" do
    @tag :typst
    test "sends it for an order paid in person", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})

      {:ok, order} =
        Orders.record_in_person_payment(order, "134.00", :cash, actor: ctx.admin)

      {:ok, order} = Orders.email_receipt(order, actor: ctx.admin)

      assert order.receipt_emailed_at
      assert_email_sent(fn email -> assert [_receipt] = email.attachments end)
    end

    @tag :typst
    test "after collection, doesn't promise to have the order ready", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false, locale: "en-GB"})
      {:ok, order} = Orders.record_in_person_payment(order, "134.00", :cash, actor: ctx.admin)
      {:ok, order} = Orders.mark_order_fulfilled(order, actor: ctx.admin)

      {:ok, _order} = Orders.email_receipt(order, actor: ctx.admin)

      assert_email_sent(fn email ->
        refute email.text_body =~ "ready on"
        assert email.text_body =~ "Thank you for your order."
      end)
    end

    test "refuses an unpaid order", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})

      assert {:error, error} = Orders.email_receipt(order, actor: ctx.admin)
      assert Exception.message(error) =~ "is not paid yet"
    end
  end
end

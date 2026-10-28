defmodule Edenflowers.Orders.CustomOrderTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.External.HereAPI
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendOrderDetailsEmail
  alias Edenflowers.Payments
  alias EdenflowersWeb.Admin.OrderLog

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

  defp tomorrow, do: Date.add(Edenflowers.ShopTime.today(), 1)

  defp custom_line(tax_rate, attrs \\ %{}) do
    Map.merge(
      %{
        "kind" => "custom",
        "product_name" => "Funeral spray",
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

  defp card(ctx, attrs) do
    product = generate(product(tax_rate_id: ctx.tax_rate.id))
    generate(product_variant(Keyword.merge([product_id: product.id], attrs)))
  end

  defp card_lines(order) do
    for line <- Ash.load!(order, :line_items, authorize?: false).line_items, line.is_card, do: line
  end

  defp line_errors(error, index) do
    for %{path: [:line_items, ^index], field: field} = e <- Ash.Error.to_error_class(error).errors,
        do: {field, e.message}
  end

  defp stub_geocoding(distance_m) do
    stub(HereAPI.Mock, :geocode, fn _query -> {:ok, {"Kyrkvägen 5, Vasa", "63.09,21.61", "here:1"}} end)
    stub(HereAPI.Mock, :route_distance, fn _position -> {:ok, distance_m} end)
  end

  describe "placing a custom order" do
    test "broadcasts a newly placed order to open admin pages", ctx do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "admin:orders")

      assert {:ok, %{id: id}} = place(ctx)

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "admin:orders",
        event: "place_custom",
        payload: %{data: %{id: ^id}}
      }
    end

    test "is placed straight away, unpaid, with its own reference", ctx do
      {:ok, order} = place(ctx)

      order = Ash.load!(order, [:grand_total, :unpaid?, :vat, line_items: [:subtotal]], authorize?: false)

      assert order.state == :placed
      assert order.origin == :custom
      assert order.payment_status == :pending
      assert order.unpaid?
      assert order.order_reference
      assert order.ordered_at
      assert order.user_id == nil
      assert order.id in Enum.map(Orders.list_orders_to_fulfil!(actor: ctx.admin), & &1.id)
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
      {:ok, in_person} = place(ctx, %{payment_terms: :invoice})

      assert is_binary(with_link.payment_link_token)
      assert in_person.payment_link_token == nil
    end

    test "needs a phone number, an email or an Instagram handle", ctx do
      assert {:error, error} = place(ctx, %{customer_phone_number: nil})
      assert Exception.message(error) =~ "enter a phone number, an email or an Instagram handle"

      assert {:ok, _order} = place(ctx, %{customer_phone_number: nil, customer_email: "son@example.com"})
      assert {:ok, _order} = place(ctx, %{customer_phone_number: nil, customer_instagram: "@anna.holm"})
    end

    test "carries a card message without a card in its lines", ctx do
      {:ok, order} = place(ctx, %{gift: true, card_message: "With deepest sympathy"})

      assert order.card_message == "With deepest sympathy"

      assert {:error, error} = place(ctx, %{gift: true, card_message: String.duplicate("a", 201)})
      assert Exception.message(error) =~ "at most 200 characters"
    end

    test "adds the chosen card as the order's card, limiting the message to its size", ctx do
      small = card(ctx, size: :small, price: "3.00")

      {:ok, order} = place(ctx, %{gift: true, recipient_name: "Ada", card_variant_id: small.id, card_message: "Hi"})

      assert [%{product_variant_id: id, quantity: 1}] = card_lines(order)
      assert id == small.id

      assert {:error, error} =
               place(ctx, %{gift: true, card_variant_id: small.id, card_message: String.duplicate("a", 81)})

      assert Exception.message(error) =~ "at most 80 characters"
    end

    test "adds no card when the flowers are for the customer", ctx do
      {:ok, order} = place(ctx, %{gift: false, card_variant_id: card(ctx, []).id})

      assert card_lines(order) == []
    end

    test "keeps a recipient and card only when the flowers are for somebody else", ctx do
      recipient = %{recipient_name: "St. Olof's church", recipient_phone_number: "040 765 4321", card_message: "Rest"}

      {:ok, gift} = place(ctx, Map.put(recipient, :gift, true))
      {:ok, for_herself} = place(ctx, Map.put(recipient, :gift, false))

      assert gift.gift
      assert gift.recipient_name == "St. Olof's church"
      assert gift.recipient_phone_number
      assert gift.card_message == "Rest"

      refute for_herself.gift
      assert for_herself.recipient_name == nil
      assert for_herself.recipient_phone_number == nil
      assert for_herself.card_message == nil
    end

    test "needs at least one valid item", ctx do
      assert {:error, error} = place(ctx, %{line_items: []})
      assert Exception.message(error) =~ "Add at least one item"

      assert {:error, error} = place(ctx, %{line_items: [custom_line(ctx.tax_rate, %{"unit_price" => "lots"})]})
      assert {:unit_price, "enter a price"} in line_errors(error, 0)

      assert {:error, error} =
               place(ctx, %{
                 line_items: [catalogue_line(ctx.variant), custom_line(ctx.tax_rate, %{"product_name" => "  "})]
               })

      assert line_errors(error, 0) == []
      assert {:product_name, "describe the item"} in line_errors(error, 1)
    end

    test "only Jennie can place one", ctx do
      {:ok, customer} = Edenflowers.Accounts.upsert_user("customer@example.com", "A Customer", authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} = Orders.place_custom_order(params(ctx), actor: customer)

      assert {:error, %Ash.Error.Forbidden{}} = Orders.place_custom_order(params(ctx), actor: nil)
    end

    test "queues the order details email when the customer has an email", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", payment_terms: :payment_link})

      assert_enqueued(worker: SendOrderDetailsEmail, args: %{"primary_key" => %{"id" => order.id}})

      Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.to == [{"", "son@example.com"}]
        assert email.text_body =~ "Funeral spray"
        assert email.text_body =~ EdenflowersWeb.PaymentLink.url_for(order)
      end)
    end

    test "an edit emails Order updated only when Jennie ticks it, with her message", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", locale: "en-GB"})
      Oban.drain_queue(queue: :default)
      assert_email_sent(fn email -> assert email.text_body =~ "Here is what we agreed" end)

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{customer_email: "son@example.com", locale: "en-GB"}), actor: ctx.admin)

      Oban.drain_queue(queue: :default)
      refute_email_sent()

      {:ok, _order} =
        Orders.edit_order(
          order,
          params(ctx, %{
            customer_email: "son@example.com",
            locale: "en-GB",
            email_customer?: true,
            message: "Lilies instead, as agreed."
          }),
          actor: ctx.admin
        )

      Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.subject =~ "Your updated Eden Flowers order for"
        assert email.text_body =~ ~r/I've updated your order\.\n\nLilies instead, as agreed\.\n\n/
        refute email.text_body =~ "Here is what we agreed"
        assert email.text_body =~ "If anything doesn't look right, just reply."
      end)
    end

    test "sent after pickup, leaves out when to collect", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", locale: "en-GB", payment_terms: :invoice})
      Oban.drain_queue(queue: :default)
      assert_email_sent()

      order = Ash.Seed.update!(order, %{fulfillment_status: :fulfilled})
      {:ok, _order} = Orders.send_order_details_email(order, actor: ctx.admin)

      assert_email_sent(fn email ->
        refute email.text_body =~ "Collect on"
        refute email.text_body =~ "I hope you're happy with it"
        assert email.text_body =~ "Here is what we agreed"
      end)
    end

    test "with an invoice, says it comes after pickup", ctx do
      {:ok, _order} = place(ctx, %{customer_email: "son@example.com", locale: "en-GB", payment_terms: :invoice})
      Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.text_body =~
                 ~r/Collect on [^\n]+ from Minimossen[^\n]+\n\nI'll send you an invoice after you've collected your order\./
      end)
    end

    test "once paid, promises no invoice", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", locale: "en-GB", payment_terms: :invoice})
      Oban.drain_queue(queue: :default)
      assert_email_sent()

      {:ok, order} = Orders.record_payment(order, "134.00", :cash, actor: ctx.admin)
      {:ok, _order} = Orders.send_order_details_email(order, actor: ctx.admin)

      assert_email_sent(fn email ->
        refute email.text_body =~ "invoice"
        assert email.text_body =~ "Paid in full"
      end)
    end

    test "sends nothing when Jennie chooses not to", ctx do
      {:ok, _order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})

      refute_enqueued(worker: SendOrderDetailsEmail)
    end
  end

  describe "the time of day" do
    test "is any time, an exact time or a window", ctx do
      {:ok, any} = place(ctx, %{fulfillment_time: :any, fulfillment_time_start: ~T[14:00:00]})

      {:ok, at} =
        place(ctx, %{fulfillment_time: :at, fulfillment_time_start: ~T[14:00:00], fulfillment_time_end: ~T[15:00:00]})

      {:ok, between} =
        place(ctx, %{
          fulfillment_time: :between,
          fulfillment_time_start: ~T[14:00:00],
          fulfillment_time_end: ~T[15:00:00]
        })

      assert {any.fulfillment_time_start, any.fulfillment_time_end} == {nil, nil}
      assert {at.fulfillment_time_start, at.fulfillment_time_end} == {~T[14:00:00], nil}
      assert {between.fulfillment_time_start, between.fulfillment_time_end} == {~T[14:00:00], ~T[15:00:00]}
    end

    test "needs its times, and a window that ends after it starts", ctx do
      assert {:error, error} = place(ctx, %{fulfillment_time: :at})
      assert Exception.message(error) =~ "Enter a time"

      assert {:error, error} =
               place(ctx, %{
                 fulfillment_time: :between,
                 fulfillment_time_start: ~T[14:00:00],
                 fulfillment_time_end: ~T[14:00:00]
               })

      assert Exception.message(error) =~ "Must be after the start"
    end

    test "is kept when an edit doesn't choose again, and goes in the order details email", ctx do
      {:ok, order} =
        place(ctx, %{
          customer_email: "son@example.com",
          locale: "sv-FI",
          fulfillment_time: :between,
          fulfillment_time_start: ~T[14:00:00],
          fulfillment_time_end: ~T[15:00:00]
        })

      Oban.drain_queue(queue: :default)
      assert_email_sent(fn email -> assert email.text_body =~ ", 14.00–15.00" end)

      order = Orders.get_order_for_admin!(order.id, actor: ctx.admin)

      {:ok, edited} =
        Orders.edit_order(order, %{florist_note: "Ring first", line_items: [custom_line(ctx.tax_rate)]},
          actor: ctx.admin
        )

      assert {edited.fulfillment_time_start, edited.fulfillment_time_end} == {~T[14:00:00], ~T[15:00:00]}
    end
  end

  describe "a delivery" do
    test "saves without a recipient phone, and is flagged until it has one", ctx do
      stub_geocoding(8_000)
      delivery = %{fulfillment_option_id: ctx.delivery.id, delivery_address: "Kyrkvägen 5"}

      {:ok, gift} = place(ctx, Map.merge(delivery, %{gift: true, recipient_name: "Grandma"}))
      {:ok, gift_with_phone} = place(ctx, Map.merge(delivery, %{gift: true, recipient_phone_number: "040 765 4321"}))
      {:ok, own} = place(ctx, delivery)
      {:ok, own_no_phone} = place(ctx, Map.merge(delivery, %{customer_phone_number: nil, customer_email: "a@b.fi"}))
      {:ok, pickup} = place(ctx, %{gift: true, recipient_name: "Grandma"})

      flagged? = &Ash.load!(&1, :missing_delivery_phone?, authorize?: false).missing_delivery_phone?

      assert flagged?.(gift)
      refute flagged?.(gift_with_phone)
      refute flagged?.(own)
      assert flagged?.(own_no_phone)
      refute flagged?.(pickup)
    end

    test "still needs a method and a date", ctx do
      assert {:error, %{errors: errors}} = place(ctx, %{fulfillment_option_id: nil, fulfillment_date: nil})

      assert errors |> Enum.map(& &1.field) |> Enum.sort() == [:fulfillment_date, :fulfillment_option_id]
    end
  end

  describe "the delivery fee" do
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
      assert order.user_id == old_user.id

      {:ok, order} = Orders.edit_order(order, params(ctx, %{customer_email: nil}), actor: ctx.admin)

      assert order.user_id == nil
      assert Orders.list_my_orders!(actor: old_user) == []
    end

    test "a stale line id is a validation error", ctx do
      {:ok, order} = place(ctx)
      stale = %{"id" => Ash.UUID.generate(), "quantity" => "1"}

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
      {:ok, order} = Orders.record_payment(order, "134.00", :zettle, actor: ctx.admin)

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{line_items: [catalogue_line(ctx.variant)]}), actor: ctx.admin)

      order = Ash.load!(order, [:balance], authorize?: false)
      assert Decimal.equal?(order.balance, "-85.00")

      {:ok, _order} = Ash.update(order, %{amount: "85.00", payment_method: :cash}, action: :refund, actor: ctx.admin)
      assert Decimal.equal?(Orders.get_order_for_admin!(order.id, actor: ctx.admin).balance, "0.00")
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
      assert Decimal.equal?(order.fulfillment_fee, "13.00")
      assert order.position == "63.09,21.61"
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      kept = [%{"id" => line_item.id, "quantity" => "1"}]

      stub_geocoding(12_000)

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{delivery | delivery_address: "Kyrkvägen 5", line_items: kept}),
          actor: ctx.admin
        )

      assert Decimal.equal?(order.fulfillment_fee, "17.00")
      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      [edit | _placed] = OrderLog.entries(versions, [], "en-GB")

      assert edit.title == "Edited"
      assert {"Delivery address", "Kyrkvägen 5"} in edit.details
      assert {"Fulfillment fee", "17,00 €"} in edit.details
      refute List.keymember?(edit.details, "Items", 0)
      assert length(OrderLog.entries(versions, [], "en-GB")) == 2
    end

    test "the log lists the items when they change", ctx do
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.variant)]})
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      kept = %{"id" => line_item.id, "quantity" => "2"}

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{line_items: [kept, custom_line(ctx.tax_rate)]}), actor: ctx.admin)

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      [edit, placed] = OrderLog.entries(versions, [], "en-GB")

      assert {"Items", ["2 × Spring Bouquet", "1 × Funeral spray"]} in edit.details
      assert {"Items", ["1 × Spring Bouquet"]} in placed.details
    end

    test "the log names the language an edit switched to", ctx do
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.variant)]})
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      kept = %{"id" => line_item.id, "quantity" => "1"}

      {:ok, order} = Orders.edit_order(order, params(ctx, %{locale: "fi", line_items: [kept]}), actor: ctx.admin)

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      [edit | _placed] = OrderLog.entries(versions, [], "en-GB")

      assert {"Language", "Suomi"} in edit.details
    end

    test "an edit that changes nothing leaves no entry in the log", ctx do
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.variant)]})
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      kept = %{"id" => line_item.id, "quantity" => "1"}

      {:ok, order} = Orders.edit_order(order, params(ctx, %{line_items: [kept]}), actor: ctx.admin)

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      assert [%{title: "Placed by Jennie"}] = OrderLog.entries(versions, [], "en-GB")
    end

    test "a line the order already has keeps the price it was sold at", ctx do
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.variant)]})
      [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
      Ash.Seed.update!(ctx.variant, %{price: Decimal.new("60.00")})

      kept = %{"id" => line_item.id, "quantity" => "2"}
      {:ok, order} = Orders.edit_order(order, params(ctx, %{line_items: [kept]}), actor: ctx.admin)

      assert [%{id: id, quantity: 2, unit_price: price}] = Ash.load!(order, :line_items, authorize?: false).line_items
      assert id == line_item.id
      assert Decimal.equal?(price, "49.00")
    end

    test "an online order keeps its card, at the price it was sold at", ctx do
      card = card(ctx, price: "4.00")
      order = online_order_with_card(ctx, card)
      Ash.Changeset.for_update(card, :update, %{price: "6.00"}) |> Ash.update!(authorize?: false)

      {:ok, order} = Orders.edit_order(order, edit_params(ctx, %{card_variant_id: card.id}), actor: ctx.admin)

      assert [%{product_variant_id: id, unit_price: price}] = card_lines(order)
      assert id == card.id
      assert Decimal.equal?(price, "4.00")
    end

    test "choosing another card replaces the order's card", ctx do
      order = online_order_with_card(ctx, card(ctx, []))
      other = card(ctx, [])

      {:ok, order} = Orders.edit_order(order, edit_params(ctx, %{card_variant_id: other.id}), actor: ctx.admin)

      assert [%{product_variant_id: id}] = card_lines(order)
      assert id == other.id
    end

    test "the card goes with no card chosen, or when the flowers are for the customer", ctx do
      card = card(ctx, [])

      {:ok, no_card} = Orders.edit_order(online_order_with_card(ctx, card), edit_params(ctx, %{}), actor: ctx.admin)

      {:ok, for_customer} =
        Orders.edit_order(
          online_order_with_card(ctx, card),
          edit_params(ctx, %{gift: false, card_variant_id: card.id}),
          actor: ctx.admin
        )

      assert card_lines(no_card) == []
      assert card_lines(for_customer) == []
    end

    test "the florist note can change on any order, even a fulfilled one", ctx do
      order = generate(order(state: :placed, fulfillment_status: :fulfilled))

      {:ok, order} = Orders.update_florist_note(order, %{florist_note: "White only, no lilies"}, actor: ctx.admin)

      assert order.florist_note == "White only, no lilies"

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      [change | _] = OrderLog.entries(versions, [], "en-GB")
      assert change.title == "Florist note changed"
      assert change.details == [{nil, "White only, no lilies"}]
    end
  end

  defp online_order_with_card(ctx, card) do
    order =
      generate(
        order(
          state: :placed,
          customer_name: "Ada",
          customer_email: "ada@example.com",
          fulfillment_option_id: ctx.pickup.id,
          fulfillment_method: :pickup,
          fulfillment_date: tomorrow(),
          gift: true,
          recipient_name: "Bea",
          card_message: "Happy birthday",
          locale: "en-GB"
        )
      )

    generate(line_item(order_id: order.id, product_variant_id: card.id, is_card: true))
    order
  end

  defp edit_params(ctx, overrides) do
    Map.merge(
      %{
        customer_name: "Ada",
        customer_email: "ada@example.com",
        fulfillment_option_id: ctx.pickup.id,
        fulfillment_date: tomorrow(),
        gift: true,
        recipient_name: "Bea",
        line_items: [catalogue_line(ctx.variant)]
      },
      overrides
    )
  end

  describe "cancelling" do
    test "takes the order off the list to fulfil and closes its payment link", ctx do
      {:ok, order} = place(ctx)
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})

      expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_link"} ->
        {:ok, %{id: "pi_link", status: "canceled"}}
      end)

      {:ok, order} = Orders.cancel_order(order, actor: ctx.admin)

      assert order.fulfillment_status == :cancelled
      assert order.cancelled_at
      refute order.payment_link_open?
      refute order.id in Enum.map(Orders.list_orders_to_fulfil!(actor: ctx.admin), & &1.id)
    end

    test "Stripe cancelling the PaymentIntent leaves a cancelled order alone", ctx do
      {:ok, order} = place(ctx)
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})
      stub(StripeAPI.Mock, :cancel_payment_intent, fn intent -> {:ok, Map.put(intent, :status, "canceled")} end)
      {:ok, _order} = Orders.cancel_order(order, actor: ctx.admin)

      {:ok, :unchanged} = Payments.cancel(%{id: "pi_link", metadata: %{"order_id" => order.id}})

      assert Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status]).payment_status == nil
    end

    test "money paid outside Stripe can be handed back, but no new money taken", ctx do
      {:ok, order} = place(ctx)
      {:ok, order} = Orders.record_payment(order, "134.00", :cash, actor: ctx.admin)
      {:ok, order} = Orders.cancel_order(order, actor: ctx.admin)

      assert {:error, error} = Orders.record_payment(order, "10.00", :cash, actor: ctx.admin)
      assert Exception.message(error) =~ "That's more than is owed"

      {:ok, order} =
        Ash.update(order, %{amount: "134.00", payment_method: :mobilepay}, action: :refund, actor: ctx.admin)

      assert order.payment_status == :refunded
      assert Decimal.equal?(order.paid_outside_stripe, 0)
    end
  end

  describe "retaining cancelled purchases" do
    test "cancellation retains its lines, VAT and history while returning stock once", ctx do
      wreath = generate(product_variant(product_id: ctx.variant.product_id, size: :large, stock_quantity: 3))
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(wreath, "2")]})
      {:ok, order} = Orders.update_florist_note(order, %{florist_note: "Test"}, actor: ctx.admin)

      original = Ash.load!(order, [:line_items, :paper_trail_versions], authorize?: false)
      assert {:ok, cancelled} = Orders.cancel_order(order, %{email_customer?: false}, actor: ctx.admin)
      retained = Ash.load!(cancelled, [:line_items, :paper_trail_versions], authorize?: false)

      assert retained.id == original.id
      assert retained.order_reference == original.order_reference
      assert retained.vat_breakdown == original.vat_breakdown
      assert Enum.map(retained.line_items, & &1.id) == Enum.map(original.line_items, & &1.id)

      assert Enum.all?(original.paper_trail_versions, fn version ->
               Enum.any?(retained.paper_trail_versions, &(&1.id == version.id))
             end)

      assert Ash.get!(Edenflowers.Catalog.ProductVariant, wreath.id, authorize?: false).stock_quantity == 3
      assert {:error, _already_cancelled} = Orders.cancel_order(cancelled, actor: ctx.admin)
      assert Ash.get!(Edenflowers.Catalog.ProductVariant, wreath.id, authorize?: false).stock_quantity == 3
    end

    test "retains undone payment history after cancellation", ctx do
      {:ok, order} = place(ctx)
      {:ok, order} = Orders.record_payment(order, "134.00", :cash, actor: ctx.admin)
      [payment] = Ash.load!(order, :payments, authorize?: false).payments
      {:ok, order} = Orders.undo_payment(order, payment.id, actor: ctx.admin)

      assert {:ok, cancelled} = Orders.cancel_order(order, %{email_customer?: false}, actor: ctx.admin)
      payments = Ash.load!(cancelled, :payments, authorize?: false).payments
      assert length(payments) == 2
      assert Enum.any?(payments, &(&1.id == payment.id))
      assert Enum.any?(payments, &(&1.reverses_payment_id == payment.id))
    end

    test "only the empty unused cart purge can physically delete orders" do
      assert [%{name: :purge_abandoned_cart}] =
               Enum.filter(Ash.Resource.Info.actions(Edenflowers.Orders.Order), &(&1.type == :destroy))

      placed = generate(order(state: :placed, updated_at: DateTime.add(DateTime.utc_now(), -2, :day)))
      assert {:error, _not_a_cart} = Ash.destroy(placed, action: :purge_abandoned_cart, authorize?: false)
      assert Orders.get_order_by_id!(placed.id, authorize?: false).state == :placed
    end
  end

  describe "stock" do
    setup ctx do
      %{wreath: generate(product_variant(product_id: ctx.variant.product_id, size: :large, stock_quantity: 3))}
    end

    defp stock(variant), do: Ash.get!(Edenflowers.Catalog.ProductVariant, variant.id, authorize?: false).stock_quantity

    test "placing takes tracked sizes off the shelf and leaves unlimited ones alone", ctx do
      {:ok, _order} = place(ctx, %{line_items: [catalogue_line(ctx.wreath, "2"), catalogue_line(ctx.variant)]})

      assert stock(ctx.wreath) == 1
      assert stock(ctx.variant) == nil
    end

    test "placing more than is left is allowed, stops at 0 and logs nothing", ctx do
      log =
        capture_log(fn ->
          assert {:ok, _order} = place(ctx, %{line_items: [catalogue_line(ctx.wreath, "5")]})
        end)

      assert stock(ctx.wreath) == 0
      refute log =~ "of variant #{ctx.wreath.id}"
    end

    test "editing takes or returns only the difference", ctx do
      other = generate(product_variant(product_id: ctx.variant.product_id, size: :small, stock_quantity: 4))
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.wreath, "1")]})
      assert stock(ctx.wreath) == 2

      {:ok, order} =
        Orders.edit_order(order, params(ctx, %{line_items: [catalogue_line(ctx.wreath, "3")]}), actor: ctx.admin)

      assert stock(ctx.wreath) == 0

      {:ok, _order} =
        Orders.edit_order(order, params(ctx, %{line_items: [catalogue_line(other, "1")]}), actor: ctx.admin)

      assert stock(ctx.wreath) == 3
      assert stock(other) == 3
    end

    test "editing an Online Order returns its old lines and takes its new ones", ctx do
      # As if placing it had already taken 1 of 4.
      order = generate(order(origin: :online, state: :placed))
      line_item = generate(line_item(order_id: order.id, product_variant_id: ctx.wreath.id, quantity: 1))

      line = %{"id" => line_item.id, "quantity" => "2"}
      {:ok, _order} = Orders.edit_order(order, params(ctx, %{line_items: [line]}), actor: ctx.admin)

      assert stock(ctx.wreath) == 2
    end

    test "a cart can't be cancelled, as it has taken no stock to return", ctx do
      order = generate(order(state: :payment))
      generate(line_item(order_id: order.id, product_variant_id: ctx.wreath.id, quantity: 2))

      assert {:error, _} = Orders.cancel_order(order, actor: ctx.admin)
      assert stock(ctx.wreath) == 3
    end

    test "cancelling a subscription's order returns nothing, as it never took stock", ctx do
      order = generate(order(origin: :subscription, state: :placed))
      generate(line_item(order_id: order.id, product_variant_id: ctx.wreath.id, quantity: 2))

      {:ok, _order} = Orders.cancel_order(order, actor: ctx.admin)

      assert stock(ctx.wreath) == 3
    end

    test "a fulfilled order can't be cancelled, so its stock stays taken", ctx do
      {:ok, order} = place(ctx, %{line_items: [catalogue_line(ctx.wreath, "2")]})
      order = Ash.Seed.update!(order, %{fulfillment_status: :fulfilled})

      assert {:error, _} = Orders.cancel_order(order, actor: ctx.admin)
      assert stock(ctx.wreath) == 1
    end

    test "an order cancelled since Jennie loaded it can't be cancelled again, so stock comes back once", ctx do
      {:ok, stale} = place(ctx, %{line_items: [catalogue_line(ctx.wreath, "2")]})
      {:ok, _order} = Orders.cancel_order(stale, actor: ctx.admin)

      assert {:error, _} = Orders.cancel_order(stale, actor: ctx.admin)
      assert stock(ctx.wreath) == 3
    end

    test "an order fulfilled since Jennie loaded it can't be cancelled", ctx do
      {:ok, stale} = place(ctx, %{line_items: [catalogue_line(ctx.wreath, "2")]})
      {:ok, _order} = Orders.mark_order_fulfilled(stale, actor: ctx.admin)

      assert {:error, _} = Orders.cancel_order(stale, actor: ctx.admin)
      assert Orders.get_order_by_id!(stale.id, authorize?: false).fulfillment_status == :fulfilled
      assert stock(ctx.wreath) == 1
    end

    test "an order cancelled since Jennie opened the form can't be edited", ctx do
      {:ok, stale} = place(ctx, %{line_items: [catalogue_line(ctx.wreath, "2")]})
      {:ok, _order} = Orders.cancel_order(stale, actor: ctx.admin)

      assert {:error, _} =
               Orders.edit_order(stale, params(ctx, %{line_items: [catalogue_line(ctx.wreath, "1")]}), actor: ctx.admin)

      order = Orders.get_order_by_id!(stale.id, authorize?: false, load: [:line_items])
      assert order.fulfillment_status == :cancelled
      assert [%{quantity: 2}] = order.line_items
      assert stock(ctx.wreath) == 3
    end
  end

  describe "paying" do
    test "a recorded payment says how it was paid and sends no receipt by itself", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})

      {:ok, order} =
        Orders.record_payment(order, "130.00", :zettle, actor: ctx.admin)

      order = Orders.get_order_for_admin!(order.id, actor: ctx.admin, load: [:payments])
      assert order.payment_status == :pending

      assert [%{method: :zettle, payment_method_type: "zettle", card_brand: nil, payment_intent_id: nil}] =
               order.payments

      assert Decimal.equal?(order.balance, "4.00")
      assert order.payment_link_open?

      Oban.drain_queue(queue: :default)
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendPaymentReceivedEmail)
      assert_no_email_sent()
    end

    test "payment status follows the balance", ctx do
      {:ok, order} = place(ctx)

      {:ok, partial} = Orders.record_payment(order, "10.00", :cash, actor: ctx.admin)
      assert partial.payment_status == :pending

      {:ok, paid} = Orders.record_payment(partial, "124.00", :cash, actor: ctx.admin)
      assert paid.payment_status == :paid
    end

    test "a free order owes nothing", ctx do
      {:ok, order} = place(ctx, %{line_items: [custom_line(ctx.tax_rate, %{"unit_price" => "0,00"})]})

      order = Ash.load!(order, [:unpaid?, :payable?], authorize?: false)
      assert order.payment_status == :paid
      refute order.unpaid?
      refute order.payable?
    end

    test "through the payment link records the payment and emails Payment received", ctx do
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

      assert_enqueued(
        worker: Edenflowers.Orders.Workers.SendPaymentReceivedEmail,
        args: %{"primary_key" => %{"id" => order.id}, "action_arguments" => %{"amount" => "134.00"}}
      )
    end

    test "through the payment link after paying in person is still recorded, and reported to refund", ctx do
      {:ok, order} = place(ctx)
      order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})
      stub(StripeAPI.Mock, :cancel_payment_intent, fn _intent -> {:error, :already_succeeded} end)

      capture_log(fn ->
        {:ok, _order} =
          Orders.record_payment(order, "134.00", :zettle, actor: ctx.admin)
      end)

      log =
        capture_log(fn ->
          assert {:ok, :completed} =
                   Payments.complete(%{id: "pi_link", metadata: %{"order_id" => order.id}, amount_received: 13_400})
        end)

      assert log =~ "Order #{order.id} is overpaid by 134.00"
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
        Orders.record_payment(order, "134.00", :cash, actor: ctx.admin)

      {:ok, order} = Orders.email_receipt(order, actor: ctx.admin)

      assert order.receipt_emailed_at
      assert_email_sent(fn email -> assert [_receipt] = email.attachments end)
    end

    @tag :typst
    test "for an order collected and paid in full, sends the receipt for the purchase", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false, locale: "en-GB"})
      {:ok, order} = Orders.record_payment(order, "134.00", :cash, actor: ctx.admin)
      {:ok, order} = Orders.mark_order_fulfilled(order, actor: ctx.admin)

      {:ok, _order} = Orders.email_receipt(order, actor: ctx.admin)

      assert_email_sent(fn email ->
        refute email.text_body =~ "Thank you for your order"
        refute email.text_body =~ "shop"
        assert email.subject == "Your receipt from Eden Flowers"
        assert email.text_body =~ "Thank you for your purchase. Your receipt is attached."
      end)
    end

    test "refuses an unpaid order", ctx do
      {:ok, order} = place(ctx, %{customer_email: "son@example.com", email_customer?: false})

      assert {:error, error} = Orders.email_receipt(order, actor: ctx.admin)
      assert Exception.message(error) =~ "is not paid yet"
    end
  end
end

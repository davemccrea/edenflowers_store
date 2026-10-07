defmodule Edenflowers.Orders.SubscriptionTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.{LineItem, Order, Subscription}
  alias Edenflowers.Payments

  setup :verify_on_exit!

  setup do
    tax_rate = generate(tax_rate())

    subscription_variant =
      generate(
        product_variant(
          product_id: generate(product(tax_rate_id: tax_rate.id, subscribable: true, free_delivery: true)).id,
          size: :medium
        )
      )

    bouquet_variant = generate(product_variant(product_id: generate(product(tax_rate_id: tax_rate.id)).id))
    delivery = generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :delivery))
    pickup = generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :pickup))

    %{
      subscription_variant: subscription_variant,
      bouquet_variant: bouquet_variant,
      delivery: delivery,
      pickup: pickup
    }
  end

  test "a subscription product must have free delivery" do
    assert {:error, %Ash.Error.Invalid{errors: [%{field: :free_delivery}]}} =
             Ash.Changeset.for_create(Edenflowers.Catalog.Product, :create, %{
               name: "Subscription",
               description: "Florist's choice",
               image_slug: "image.png",
               tax_rate_id: generate(tax_rate()).id,
               product_category_id: generate(product_category()).id,
               subscribable: true,
               free_delivery: false
             })
             |> Ash.create(authorize?: false)
  end

  describe "a subscription cart" do
    test "holds the subscription alone, with a card if wanted", ctx do
      order = generate(order())
      generate(line_item(order_id: order.id, product_variant_id: ctx.subscription_variant.id))

      assert {:error, _} = Orders.add_line_item(order.id, ctx.bouquet_variant.id, 1, authorize?: false)
      assert {:error, _} = Orders.add_line_item(order.id, ctx.subscription_variant.id, 1, authorize?: false)
      assert {:ok, _} = Orders.add_line_item(order.id, ctx.bouquet_variant.id, 1, %{is_card: true}, authorize?: false)
    end

    test "can't be added to a cart that already holds something", ctx do
      order = generate(order())
      generate(line_item(order_id: order.id, product_variant_id: ctx.bouquet_variant.id))

      assert {:error, _} = Orders.add_line_item(order.id, ctx.subscription_variant.id, 1, authorize?: false)
    end

    test "is for one bouquet", ctx do
      order = generate(order())
      line_item = generate(line_item(order_id: order.id, product_variant_id: ctx.subscription_variant.id))

      assert %LineItem{quantity: 1} = Orders.increment_line_item!(line_item, authorize?: false)
    end

    test "rejects pickup", ctx do
      order = subscription_cart(ctx, state: :delivery)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               submit_delivery(order, %{fulfillment_option_id: ctx.pickup.id, subscription_interval_weeks: 2})

      assert Enum.any?(errors, &(&1.field == :fulfillment_option_id))
    end

    test "must say how often", ctx do
      order = subscription_cart(ctx, state: :delivery)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               submit_delivery(order, %{fulfillment_option_id: ctx.delivery.id, subscription_interval_weeks: 3})

      assert Enum.any?(errors, &(&1.field == :subscription_interval_weeks))
    end
  end

  test "paying a subscription cart saves the card to a Stripe Customer", ctx do
    order = subscription_cart(ctx, state: :payment, payment_intent_id: nil)
    order = Orders.get_order_for_checkout!(order.id, authorize?: false)
    order_id = order.id

    expect(StripeAPI.Mock, :create_customer, fn %{email: "ada@example.com", name: "Ada Lovelace"} ->
      {:ok, %{id: "cus_ada"}}
    end)

    expect(StripeAPI.Mock, :create_payment_intent_saving_card, fn _cents, %{"order_id" => ^order_id}, "cus_ada" ->
      {:ok, %{id: "pi_sub", client_secret: "pi_sub_secret", amount: 0}}
    end)

    assert {:ok, _order, "pi_sub_secret"} = Payments.setup(order, nil)
  end

  describe "when the first order is paid" do
    test "the subscription starts from it", ctx do
      order = subscription_cart(ctx, state: :payment)

      assert {:ok, :completed} = Payments.complete(payment_intent(order))

      order = Ash.get!(Order, order.id, authorize?: false)
      subscription = Ash.get!(Subscription, order.subscription_id, authorize?: false)

      assert subscription.state == :active
      assert subscription.user_id == order.user_id
      assert subscription.product_variant_id == ctx.subscription_variant.id
      assert subscription.interval_weeks == 2
      assert subscription.next_fulfillment_date == Date.add(order.fulfillment_date, 14)
      assert subscription.fulfillment_option_id == ctx.delivery.id
      assert subscription.recipient_name == "Grace Hopper"
      assert subscription.recipient_phone_number == "040 1234567"
      assert subscription.delivery_address == "Hovrättsesplanaden 1, Vasa"
      assert subscription.delivery_instructions == "Door code 1234"
      assert subscription.card_message == "Enjoy"
      assert subscription.locale == "fi"
      assert subscription.stripe_customer_id == "cus_ada"
      assert subscription.stripe_payment_method_id == "pm_card"
    end

    test "a redelivered webhook doesn't start a second one", ctx do
      order = subscription_cart(ctx, state: :payment)

      assert {:ok, :completed} = Payments.complete(payment_intent(order))
      assert {:ok, :already_completed} = Payments.complete(payment_intent(order))

      assert [_one] = Ash.read!(Subscription, authorize?: false)
    end

    test "a subscription that can't start still places the paid order", ctx do
      order = subscription_cart(ctx, state: :payment)
      payment_intent = Map.put(payment_intent(order), :payment_method, nil)

      log =
        capture_log(fn ->
          assert {:ok, :completed} = Payments.complete(payment_intent)
        end)

      assert log =~ "subscription could not be started"
      assert %{state: :placed, subscription_id: nil} = Ash.get!(Order, order.id, authorize?: false)
      assert Ash.read!(Subscription, authorize?: false) == []
    end

    test "an ordinary order starts none", ctx do
      order = subscription_cart(ctx, state: :payment, variant: ctx.bouquet_variant)

      assert {:ok, :completed} = Payments.complete(payment_intent(order))

      assert Ash.read!(Subscription, authorize?: false) == []
    end
  end

  defp subscription_cart(ctx, opts) do
    {variant, opts} = Keyword.pop(opts, :variant, ctx.subscription_variant)
    {:ok, user} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    order =
      generate(
        order(
          [
            customer_name: "Ada Lovelace",
            customer_email: "ada@example.com",
            user_id: user.id,
            gift: true,
            recipient_name: "Grace Hopper",
            recipient_phone_number: "040 1234567",
            delivery_address: "Hovrättsesplanaden 1, Vasa",
            delivery_instructions: "Door code 1234",
            card_message: "Enjoy",
            locale: "fi",
            fulfillment_option_id: ctx.delivery.id,
            fulfillment_method: :delivery,
            fulfillment_date: Date.add(Date.utc_today(), 3),
            subscription_interval_weeks: 2,
            quoted_fulfillment_fee: Decimal.new("0"),
            payment_intent_id: "pi_#{System.unique_integer([:positive])}"
          ] ++ opts
        )
      )

    generate(line_item(order_id: order.id, product_variant_id: variant.id))
    order
  end

  defp submit_delivery(order, params) do
    params =
      Map.merge(
        %{fulfillment_date: Date.add(Date.utc_today(), 3), recipient_phone_number: "040 1234567"},
        params
      )

    order
    |> Ash.Changeset.for_update(:submit_delivery, params)
    |> Ash.update(authorize?: false)
  end

  defp payment_intent(order) do
    order = Ash.load!(order, :grand_total, authorize?: false)

    %{
      id: order.payment_intent_id,
      status: "succeeded",
      metadata: %{"order_id" => order.id},
      amount_received: StripeAPI.to_stripe_amount(order.grand_total),
      customer: "cus_ada",
      payment_method: "pm_card"
    }
  end
end

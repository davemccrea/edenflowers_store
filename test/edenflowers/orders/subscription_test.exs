defmodule Edenflowers.Orders.SubscriptionTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.{LineItem, Order, Subscription}
  alias Edenflowers.Orders.Schedulers.StartSubscription, as: ScheduleStartSubscription
  alias Edenflowers.Orders.Workers.{SendSubscriptionSetupEmail, StartSubscription}
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
      subscribe(order, ctx.subscription_variant, 2)

      assert {:error, _} = Orders.add_line_item(order.id, ctx.bouquet_variant.id, 1, authorize?: false)
      assert {:ok, _} = Orders.add_line_item(order.id, ctx.bouquet_variant.id, 1, %{is_card: true}, authorize?: false)
    end

    test "is replaced when the same product is bought once instead", ctx do
      order = generate(order())
      subscribe(order, ctx.subscription_variant, 2)
      large = generate(product_variant(product_id: ctx.subscription_variant.product_id, size: :large))

      assert {:ok, _} = Orders.add_line_item(order.id, large.id, 1, authorize?: false)

      assert [%LineItem{product_variant_id: variant_id, quantity: 1, interval_weeks: nil}] =
               Ash.read!(LineItem, authorize?: false)

      assert variant_id == large.id
      refute Ash.load!(order, :subscription?, authorize?: false).subscription?
    end

    test "isn't replaced by a different product", ctx do
      order = generate(order())
      subscribe(order, ctx.subscription_variant, 2)

      other =
        generate(product_variant(product_id: generate(product(subscribable: true, free_delivery: true)).id))

      assert {:error, _} = subscribe(order, other, 2)
      assert {:error, _} = Orders.add_line_item(order.id, other.id, 1, authorize?: false)
      assert [%LineItem{interval_weeks: 2}] = Ash.read!(LineItem, authorize?: false)
    end

    test "is replaced by another subscription, so its size or frequency can change", ctx do
      order = generate(order())
      large = generate(product_variant(product_id: ctx.subscription_variant.product_id, size: :large))
      subscribe(order, ctx.subscription_variant, 2)
      card = Orders.add_line_item!(order.id, ctx.bouquet_variant.id, 1, %{is_card: true}, authorize?: false)

      assert {:ok, _} = subscribe(order, large, 4)
      assert {:ok, _} = subscribe(order, large, 4)

      lines = Ash.read!(LineItem, authorize?: false)
      assert [%LineItem{quantity: 1, interval_weeks: 4}] = Enum.filter(lines, &(&1.product_variant_id == large.id))
      refute Enum.any?(lines, &(&1.product_variant_id == ctx.subscription_variant.id))
      assert Enum.any?(lines, &(&1.id == card.id))
    end

    test "can't be added to a cart that already holds something", ctx do
      order = generate(order())
      generate(line_item(order_id: order.id, product_variant_id: ctx.bouquet_variant.id))

      assert {:error, _} = subscribe(order, ctx.subscription_variant, 2)
    end

    test "replaces a one-off of the same product, so a customer can switch to subscribing", ctx do
      order = generate(order())
      Orders.add_line_item!(order.id, ctx.subscription_variant.id, 1, authorize?: false)

      assert {:ok, _} = subscribe(order, ctx.subscription_variant, 2)

      assert [%LineItem{quantity: 1, interval_weeks: 2}] = Ash.read!(LineItem, authorize?: false)
      assert Ash.load!(order, :subscription?, authorize?: false).subscription?
    end

    test "doesn't replace a one-off cart that also holds another product", ctx do
      order = generate(order())
      Orders.add_line_item!(order.id, ctx.subscription_variant.id, 1, authorize?: false)
      Orders.add_line_item!(order.id, ctx.bouquet_variant.id, 1, authorize?: false)

      assert {:error, _} = subscribe(order, ctx.subscription_variant, 2)
      assert [_, _] = Ash.read!(LineItem, authorize?: false)
    end

    test "is for one bouquet", ctx do
      order = generate(order())
      {:ok, line_item} = subscribe(order, ctx.subscription_variant, 2)

      assert %LineItem{quantity: 1} = Orders.increment_line_item!(line_item, authorize?: false)
    end

    test "is refused for a product that can't be subscribed to", ctx do
      order = generate(order())

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :interval_weeks}]}} =
               subscribe(order, ctx.bouquet_variant, 2)
    end

    test "is refused for an interval other than 1, 2 or 4 weeks", ctx do
      order = generate(order())

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :interval_weeks}]}} =
               subscribe(order, ctx.subscription_variant, 3)
    end

    test "can be picked up", ctx do
      order = subscription_cart(ctx, state: :delivery)

      assert {:ok, %Order{fulfillment_method: :pickup}} =
               submit_delivery(order, %{fulfillment_option_id: ctx.pickup.id})
    end
  end

  describe "a subscribable product bought once" do
    test "shares the cart and adds up like any product", ctx do
      order = generate(order())

      Orders.add_line_item!(order.id, ctx.bouquet_variant.id, 1, authorize?: false)
      Orders.add_line_item!(order.id, ctx.subscription_variant.id, 1, authorize?: false)
      line_item = Orders.add_line_item!(order.id, ctx.subscription_variant.id, 1, authorize?: false)

      assert %LineItem{quantity: 3, interval_weeks: nil} = Orders.increment_line_item!(line_item, authorize?: false)
      refute Ash.load!(order, :subscription?, authorize?: false).subscription?
    end

    test "can be picked up and starts no subscription", ctx do
      order = subscription_cart(ctx, state: :delivery, interval_weeks: nil)

      assert {:ok, %Order{fulfillment_method: :pickup} = order} =
               submit_delivery(order, %{fulfillment_option_id: ctx.pickup.id})

      assert {:ok, :completed} = Payments.complete(payment_intent(order))

      assert Ash.read!(Subscription, authorize?: false) == []
    end
  end

  test "paying a subscription cart saves the card to a Stripe Customer", ctx do
    order = subscription_cart(ctx, state: :payment, payment_intent_id: nil)
    # Without `subscription?` loaded: setup finds that out for itself.
    order = Ash.load!(order, :grand_total, authorize?: false)
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
    test "the subscription is queued to start straight away", ctx do
      order = subscription_cart(ctx, state: :payment)

      assert {:ok, :completed} = Payments.complete(payment_intent(order))

      assert_enqueued(worker: StartSubscription, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "the subscription starts from it", ctx do
      order = subscription_cart(ctx, state: :payment)

      assert {:ok, :completed} = Payments.complete(payment_intent(order))
      start_subscriptions()

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

    test "the customer is emailed once that it is set up", ctx do
      order = subscription_cart(ctx, state: :payment)

      assert {:ok, :completed} = Payments.complete(payment_intent(order))
      start_subscriptions()

      assert [job] = all_enqueued(worker: SendSubscriptionSetupEmail)
      assert {:ok, _subscription} = perform_job(SendSubscriptionSetupEmail, job.args)

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        refute email.text_body =~ "Alennus koskee ensimmäistä toimitustasi."
        assert email.text_body =~ "Hovrättsesplanaden 1, Vasa"
        assert email.text_body =~ "Korttiviestisi tulee ensimmäisen toimituksen mukana."
      end)

      assert {:cancel, _} = perform_job(SendSubscriptionSetupEmail, job.args)
      refute_email_sent()
    end

    test "the set-up email says a promotion only discounted the first delivery", ctx do
      order =
        ctx
        |> subscription_cart(state: :payment)
        |> Orders.add_promotion_with_code!(generate(promotion()).code, authorize?: false)

      assert {:ok, :completed} = Payments.complete(payment_intent(order))
      start_subscriptions()

      assert [job] = all_enqueued(worker: SendSubscriptionSetupEmail)
      assert {:ok, _subscription} = perform_job(SendSubscriptionSetupEmail, job.args)

      assert_email_sent(fn email ->
        assert email.text_body =~ "Alennus koskee ensimmäistä toimitustasi."
      end)
    end

    test "a redelivered webhook doesn't start a second one", ctx do
      order = subscription_cart(ctx, state: :payment)

      assert {:ok, :completed} = Payments.complete(payment_intent(order))
      assert {:ok, :already_completed} = Payments.complete(payment_intent(order))
      start_subscriptions()
      start_subscriptions()

      assert [_one] = Ash.read!(Subscription, authorize?: false)
    end

    test "a subscription that can't start leaves the paid order placed, and is tried again", ctx do
      order = subscription_cart(ctx, state: :payment)
      payment_intent = Map.put(payment_intent(order), :payment_method, nil)

      assert {:ok, :completed} = Payments.complete(payment_intent)
      assert %{state: :placed, subscription_id: nil} = Ash.get!(Order, order.id, authorize?: false)

      assert :ok = perform_job(ScheduleStartSubscription, %{})
      assert [job] = all_enqueued(worker: StartSubscription)
      log = capture_log(fn -> catch_error(perform_job(StartSubscription, job.args)) end)

      assert log =~ "stripe_payment_method_id"
      assert %{state: :placed, subscription_id: nil} = Ash.get!(Order, order.id, authorize?: false)
      assert Ash.read!(Subscription, authorize?: false) == []
    end

    test "an ordinary order starts none", ctx do
      order = subscription_cart(ctx, state: :payment, variant: ctx.bouquet_variant, interval_weeks: nil)

      assert {:ok, :completed} = Payments.complete(payment_intent(order))
      start_subscriptions()

      assert Ash.read!(Subscription, authorize?: false) == []
    end
  end

  defp start_subscriptions do
    assert :ok = perform_job(ScheduleStartSubscription, %{})

    for job <- all_enqueued(worker: StartSubscription) do
      perform_job(StartSubscription, job.args)
    end
  end

  defp subscription_cart(ctx, opts) do
    {variant, opts} = Keyword.pop(opts, :variant, ctx.subscription_variant)
    {interval_weeks, opts} = Keyword.pop(opts, :interval_weeks, 2)
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
            quoted_fulfillment_fee: Decimal.new("0"),
            payment_intent_id: "pi_#{System.unique_integer([:positive])}"
          ] ++ opts
        )
      )

    generate(line_item(order_id: order.id, product_variant_id: variant.id, interval_weeks: interval_weeks))
    order
  end

  defp subscribe(order, variant, interval_weeks) do
    Orders.add_line_item(order.id, variant.id, 1, %{interval_weeks: interval_weeks}, authorize?: false)
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

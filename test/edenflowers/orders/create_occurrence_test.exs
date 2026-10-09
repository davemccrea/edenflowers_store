defmodule Edenflowers.Orders.CreateOccurrenceTest do
  use Edenflowers.DataCase, async: true

  require Ash.Query

  import ExUnit.CaptureLog
  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.Expressions.HelsinkiToday
  alias Edenflowers.External.{HereAPI, StripeAPI}
  alias Edenflowers.Orders
  alias Edenflowers.Orders.{Order, Payment, Subscription}
  alias Edenflowers.Orders.Schedulers.CreateOccurrence, as: ScheduleOccurrences
  alias Edenflowers.Orders.Workers.CreateOccurrence
  alias Edenflowers.Orders.Workers.SendConfirmationEmail
  alias Edenflowers.Orders.Workers.SendPaymentFailedEmail

  setup :verify_on_exit!

  setup do
    tax_rate = generate(tax_rate())

    variant =
      generate(
        product_variant(
          product_id: generate(product(tax_rate_id: tax_rate.id, subscribable: true, free_delivery: true)).id,
          price: "60.00"
        )
      )

    delivery =
      generate(
        fulfillment_option(
          tax_rate_id: tax_rate.id,
          fulfillment_method: :delivery,
          rate_type: :dynamic,
          base_price: "4.50"
        )
      )

    {:ok, user} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    date = Date.add(HelsinkiToday.today(), 3)

    %{variant: variant, delivery: delivery, user: user, date: date}
  end

  defp subscription(ctx, attrs \\ %{}) do
    Ash.Seed.seed!(
      Subscription,
      Map.merge(
        %{
          user_id: ctx.user.id,
          product_variant_id: ctx.variant.id,
          fulfillment_option_id: ctx.delivery.id,
          interval_weeks: 2,
          next_fulfillment_date: ctx.date,
          recipient_name: "Grace Hopper",
          recipient_phone_number: "+358401234567",
          delivery_address: "Hovrättsesplanaden 1, Vasa",
          delivery_instructions: "Door code 1234",
          card_message: "Enjoy",
          locale: "fi",
          stripe_customer_id: "cus_ada",
          stripe_payment_method_id: "pm_card"
        },
        attrs
      )
    )
  end

  defp stub_geocoding do
    stub(HereAPI.Mock, :geocode, fn _query -> {:ok, {"Hovrättsesplanaden 1, Vasa", "63.09,21.61", "here:1"}} end)
    stub(HereAPI.Mock, :route_distance, fn _position -> {:ok, 3000} end)
  end

  defp succeeded(cents, %{metadata: metadata}) do
    {:ok, %{id: "pi_occurrence", status: "succeeded", amount_received: cents, metadata: metadata}}
  end

  defp run(subscription) do
    perform_job(CreateOccurrence, %{"primary_key" => %{"id" => subscription.id}})
  end

  # A failed job raises, and Oban retries it.
  defp run_failing(subscription) do
    capture_log(fn -> catch_error(run(subscription)) end)
  end

  defp occurrences(subscription) do
    Order
    |> Ash.Query.filter(subscription_id == ^subscription.id)
    |> Ash.read!(authorize?: false, load: [:payments, :line_items, :grand_total])
  end

  defp reload(subscription), do: Ash.get!(Subscription, subscription.id, authorize?: false)

  test "creates, charges and places the order a few days before delivery, then moves on", ctx do
    subscription = subscription(ctx)
    stub_geocoding()
    {:ok, _user} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada King", authorize?: false)
    expected_key = "sub-#{subscription.id}-#{ctx.date}"

    expect(StripeAPI.Mock, :charge_off_session, fn 6000, params, ^expected_key ->
      assert %{customer: "cus_ada", payment_method: "pm_card", metadata: %{"order_id" => _}} = params
      succeeded(6000, params)
    end)

    assert :ok = perform_job(ScheduleOccurrences, %{})
    assert [%{args: args}] = all_enqueued(worker: CreateOccurrence)
    assert {:ok, _} = perform_job(CreateOccurrence, args)

    assert [order] = occurrences(subscription)
    assert order.state == :placed
    assert order.origin == :subscription
    assert order.subscription_date == ctx.date
    assert order.fulfillment_date == ctx.date
    assert order.customer_name == "Ada King"
    assert order.customer_email == "ada@example.com"
    assert order.recipient_name == "Grace Hopper"
    assert order.gift
    assert is_nil(order.card_message)
    assert order.delivery_instructions == "Door code 1234"
    assert order.locale == "fi"
    assert order.order_reference
    assert [%{product_variant_id: variant_id, free_delivery: true, interval_weeks: nil}] = order.line_items
    assert variant_id == ctx.variant.id
    assert Decimal.equal?(order.fulfillment_fee, 0)
    assert Decimal.equal?(order.grand_total, "60.00")
    assert [%Payment{method: :stripe, payment_intent_id: "pi_occurrence"} = payment] = order.payments
    assert Decimal.equal?(payment.amount, "60.00")
    assert_enqueued(worker: SendConfirmationEmail, args: %{"primary_key" => %{"id" => order.id}})

    assert reload(subscription).next_fulfillment_date == Date.add(ctx.date, 14)
  end

  test "keeps a change Jennie makes while the card is being charged", ctx do
    subscription = subscription(ctx)
    stub_geocoding()

    expect(StripeAPI.Mock, :charge_off_session, fn cents, params, _key ->
      Orders.change_subscription!(reload(subscription), %{interval_weeks: 4}, actor: generate(admin_user()))
      succeeded(cents, params)
    end)

    assert {:ok, _} = run(subscription)

    assert %{interval_weeks: 4, next_fulfillment_date: next_date} = reload(subscription)
    assert next_date == Date.add(ctx.date, 28)
  end

  test "is not picked up before its lead time", ctx do
    subscription(ctx, %{next_fulfillment_date: Date.add(ctx.date, 1)})

    assert :ok = perform_job(ScheduleOccurrences, %{})
    assert all_enqueued(worker: CreateOccurrence) == []
  end

  test "a closed day moves delivery to the next open day, but the schedule keeps its own date", ctx do
    closed = generate(fulfillment_option(fulfillment_method: :delivery, disabled_dates: [ctx.date]))
    subscription = subscription(ctx, %{fulfillment_option_id: closed.id})
    stub_geocoding()
    expect(StripeAPI.Mock, :charge_off_session, fn cents, params, _key -> succeeded(cents, params) end)

    assert {:ok, _} = run(subscription)

    assert [%{fulfillment_date: fulfillment_date, subscription_date: subscription_date}] = occurrences(subscription)
    assert fulfillment_date == Date.add(ctx.date, 1)
    assert subscription_date == ctx.date
    assert reload(subscription).next_fulfillment_date == Date.add(ctx.date, 14)
  end

  test "a closed schedule window is skipped instead of colliding with the next occurrence", ctx do
    disabled_dates = Enum.map(0..6, &Date.add(ctx.date, &1))
    closed = generate(fulfillment_option(fulfillment_method: :delivery, disabled_dates: disabled_dates))
    subscription = subscription(ctx, %{fulfillment_option_id: closed.id, interval_weeks: 1})
    stub_geocoding()
    stub(StripeAPI.Mock, :charge_off_session, fn cents, params, _key -> succeeded(cents, params) end)

    assert {:ok, _} = run(subscription)

    assert occurrences(subscription) == []
    assert reload(subscription).next_fulfillment_date == Date.add(ctx.date, 7)
  end

  test "a date missed while the job was down creates no order and is reported", ctx do
    missed = Date.add(HelsinkiToday.today(), -15)
    subscription = subscription(ctx, %{next_fulfillment_date: missed})

    log = capture_log(fn -> assert {:ok, _} = run(subscription) end)

    assert log =~ "missed its delivery"
    assert occurrences(subscription) == []
    assert reload(subscription).next_fulfillment_date == Date.add(missed, 14)
  end

  test "a past scheduled date is delivered when its first open fulfillment date is today", ctx do
    today = HelsinkiToday.today()

    delivery =
      generate(
        fulfillment_option(
          fulfillment_method: :delivery,
          same_day: true,
          order_deadline: ~T[23:59:59]
        )
      )

    subscription =
      subscription(ctx, %{fulfillment_option_id: delivery.id, next_fulfillment_date: Date.add(today, -1)})

    stub_geocoding()
    expect(StripeAPI.Mock, :charge_off_session, fn cents, params, _key -> succeeded(cents, params) end)

    assert {:ok, _} = run(subscription)
    assert [%{fulfillment_date: ^today}] = occurrences(subscription)
  end

  describe "run again" do
    test "after the order was placed, only moves the subscription on", ctx do
      subscription = subscription(ctx)
      stub_geocoding()
      expect(StripeAPI.Mock, :charge_off_session, 1, fn cents, params, _key -> succeeded(cents, params) end)

      assert {:ok, _} = run(subscription)

      # As if moving the date on had failed after the order was placed.
      Ecto.Adapters.SQL.query!(Edenflowers.Repo, "UPDATE subscriptions SET next_fulfillment_date = $1 WHERE id = $2", [
        ctx.date,
        Ecto.UUID.dump!(subscription.id)
      ])

      assert {:ok, _} = run(subscription)

      assert [%{payments: [_one_payment]}] = occurrences(subscription)
      assert reload(subscription).next_fulfillment_date == Date.add(ctx.date, 14)
    end

    test "after a failed geocode, makes the order once it can", ctx do
      subscription = subscription(ctx)
      expect(HereAPI.Mock, :geocode, fn _query -> {:error, :timeout} end)

      run_failing(subscription)
      assert occurrences(subscription) == []
      assert reload(subscription).next_fulfillment_date == ctx.date

      stub_geocoding()
      expect(StripeAPI.Mock, :charge_off_session, fn cents, params, _key -> succeeded(cents, params) end)

      assert {:ok, _} = run(subscription)
      assert [%{state: :placed}] = occurrences(subscription)
    end

    test "after a Stripe network error, charges the same order with the same key", ctx do
      subscription = subscription(ctx)
      stub_geocoding()
      network_error = %Stripe.Error{source: :network, code: :network_error, message: "timeout"}
      key = "sub-#{subscription.id}-#{ctx.date}"

      expect(StripeAPI.Mock, :charge_off_session, fn _cents, _params, ^key -> {:error, network_error} end)
      run_failing(subscription)
      assert [%{state: :payment, payments: []}] = occurrences(subscription)
      assert reload(subscription).next_fulfillment_date == ctx.date

      expect(StripeAPI.Mock, :charge_off_session, fn cents, params, ^key -> succeeded(cents, params) end)
      assert {:ok, _} = run(subscription)

      assert [%{state: :placed, payments: [_one_payment]}] = occurrences(subscription)
      assert reload(subscription).next_fulfillment_date == Date.add(ctx.date, 14)
    end

    test "after a charge that hadn't succeeded yet, asks Stripe instead of charging again", ctx do
      subscription = subscription(ctx)
      stub_geocoding()

      expect(StripeAPI.Mock, :charge_off_session, 1, fn _cents, params, _key ->
        {:ok, %{id: "pi_occurrence", status: "processing", amount_received: 0, metadata: params.metadata}}
      end)

      run_failing(subscription)
      assert [%{payment_intent_id: "pi_occurrence"} = order] = occurrences(subscription)

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: "pi_occurrence"} ->
        succeeded(StripeAPI.to_stripe_amount(order.grand_total), %{metadata: %{"order_id" => order.id}})
      end)

      assert {:ok, _} = run(subscription)
      assert [%{state: :placed, payments: [_one_payment]}] = occurrences(subscription)
    end

    test "a persisted authentication-required intent places the occurrence unpaid", ctx do
      subscription = subscription(ctx)
      stub_geocoding()

      expect(StripeAPI.Mock, :charge_off_session, fn _cents, params, _key ->
        {:ok, %{id: "pi_requires_action", status: "processing", amount_received: 0, metadata: params.metadata}}
      end)

      run_failing(subscription)
      assert [%{payment_intent_id: "pi_requires_action"}] = occurrences(subscription)

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: "pi_requires_action"} ->
        {:ok, %{id: "pi_requires_action", status: "requires_action"}}
      end)

      capture_log(fn -> assert {:ok, _} = run(subscription) end)

      assert [order] = occurrences(subscription)
      assert order.state == :placed
      assert Ash.load!(order, :unpaid?, authorize?: false).unpaid?
      assert reload(subscription).state == :payment_failed
    end
  end

  describe "a refused card" do
    setup ctx do
      stub_geocoding()
      %{subscription: subscription(ctx)}
    end

    defp refuse(card_code) do
      expect(StripeAPI.Mock, :charge_off_session, fn _cents, _params, _key ->
        {:error, %Stripe.Error{source: :stripe, code: :card_error, message: "Refused", extra: %{card_code: card_code}}}
      end)
    end

    defp run_refused(subscription) do
      capture_log(fn -> assert {:ok, _} = run(subscription) end)
    end

    for card_code <- [:card_declined, :authentication_required] do
      test "#{card_code} places the order unpaid, emails a payment link and holds the subscription", ctx do
        refuse(unquote(card_code))

        run_refused(ctx.subscription)

        assert [order] = occurrences(ctx.subscription)
        order = Ash.load!(order, [:unpaid?], authorize?: false)
        assert order.state == :placed
        assert order.unpaid?
        assert order.ordered_at
        assert order.order_reference
        assert order.payment_link_token
        assert order.payments == []

        subscription = reload(ctx.subscription)
        assert subscription.state == :payment_failed
        assert subscription.next_fulfillment_date == Date.add(ctx.date, 14)

        assert_enqueued(worker: SendPaymentFailedEmail, args: %{"primary_key" => %{"id" => order.id}})
        assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

        assert_email_sent(fn email ->
          assert email.to == [{"", "ada@example.com"}]
          assert email.subject =~ order.order_reference
          assert email.text_body =~ "/pay/#{order.payment_link_token}"
        end)
      end
    end

    test "a requires_action response places the order unpaid and holds the subscription", ctx do
      expect(StripeAPI.Mock, :charge_off_session, fn _cents, params, _key ->
        {:ok, %{id: "pi_requires_action", status: "requires_action", amount_received: 0, metadata: params.metadata}}
      end)

      run_refused(ctx.subscription)

      assert [order] = occurrences(ctx.subscription)
      assert order.state == :placed
      assert order.payment_intent_id == "pi_requires_action"
      assert Ash.load!(order, :unpaid?, authorize?: false).unpaid?
      assert reload(ctx.subscription).state == :payment_failed
    end

    test "a cancel made while the card is charged stays cancelled", ctx do
      expect(StripeAPI.Mock, :charge_off_session, fn _cents, _params, _key ->
        Orders.cancel_subscription!(reload(ctx.subscription), actor: generate(admin_user()))
        {:error, %Stripe.Error{source: :stripe, code: :card_error, message: "Refused"}}
      end)

      capture_log(fn -> assert {:cancel, :trigger_no_longer_applies} = run(ctx.subscription) end)

      assert reload(ctx.subscription).state == :cancelled
      assert [%{state: :placed}] = occurrences(ctx.subscription)
    end

    test "run again, neither charges nor emails again", ctx do
      refuse(:card_declined)
      run_refused(ctx.subscription)
      Oban.drain_queue(queue: :default)
      assert_email_sent()

      # As if moving the subscription on had failed after the order was placed.
      Ecto.Adapters.SQL.query!(
        Edenflowers.Repo,
        "UPDATE subscriptions SET next_fulfillment_date = $1, state = 'active' WHERE id = $2",
        [ctx.date, Ecto.UUID.dump!(ctx.subscription.id)]
      )

      assert {:ok, _} = run(ctx.subscription)

      assert [_one_order] = occurrences(ctx.subscription)
      assert reload(ctx.subscription).state == :payment_failed
      refute_enqueued(worker: SendPaymentFailedEmail)
      assert_no_email_sent()
    end

    test "creates no further occurrences while held", ctx do
      refuse(:card_declined)
      run_refused(ctx.subscription)

      Ecto.Adapters.SQL.query!(Edenflowers.Repo, "UPDATE subscriptions SET next_fulfillment_date = $1 WHERE id = $2", [
        ctx.date,
        Ecto.UUID.dump!(ctx.subscription.id)
      ])

      Oban.drain_queue(queue: :default)
      assert :ok = perform_job(ScheduleOccurrences, %{})
      assert all_enqueued(worker: CreateOccurrence) == []

      assert {:cancel, :trigger_no_longer_applies} = run(ctx.subscription)
      assert [_one_order] = occurrences(ctx.subscription)
    end

    test "paying the payment link reactivates the subscription", ctx do
      refuse(:authentication_required)
      run_refused(ctx.subscription)
      [order] = occurrences(ctx.subscription)

      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_link_paid",
                 type: "payment_intent.succeeded",
                 data: %{
                   object: %{
                     id: "pi_link",
                     metadata: %{"order_id" => order.id},
                     amount_received: StripeAPI.to_stripe_amount(order.grand_total)
                   }
                 }
               })

      assert [%{payments: [%Payment{payment_intent_id: "pi_link"}]}] = occurrences(ctx.subscription)
      subscription = reload(ctx.subscription)
      assert subscription.state == :active
      assert subscription.next_fulfillment_date == Date.add(ctx.date, 14)
    end

    test "paid after its next date has passed, picks up at the first date still ahead", ctx do
      refuse(:card_declined)
      run_refused(ctx.subscription)
      [order] = occurrences(ctx.subscription)

      passed = Date.add(HelsinkiToday.today(), -1)

      Ecto.Adapters.SQL.query!(Edenflowers.Repo, "UPDATE subscriptions SET next_fulfillment_date = $1 WHERE id = $2", [
        passed,
        Ecto.UUID.dump!(ctx.subscription.id)
      ])

      payment_intent = %{
        id: "pi_link",
        status: "succeeded",
        metadata: %{"order_id" => order.id},
        amount_received: StripeAPI.to_stripe_amount(order.grand_total)
      }

      assert {:ok, :completed} = Edenflowers.Payments.complete(payment_intent)

      subscription = reload(ctx.subscription)
      assert subscription.state == :active
      assert subscription.next_fulfillment_date == Date.add(passed, 14)
    end
  end
end

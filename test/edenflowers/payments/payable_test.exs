defmodule Edenflowers.Payments.PayableTest do
  @moduledoc """
  Every case runs against an order and a course booking, which is what keeps
  the two working out what's owed the same way.
  """
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Payments

  setup :verify_on_exit!

  @fields [
    :total_due,
    :committed?,
    :amount_paid,
    :paid_outside_stripe,
    :balance,
    :refunded?,
    :settled?,
    :outside_stripe_refund,
    :stripe_refund,
    :stripe_refundable?
  ]

  # An order or booking for 80.00, paid with `payments` like `[stripe: "50.00", cash: "30.00"]`.
  # `lowered: true` drops it to 40.00 after it was paid.
  defp build(parent, opts \\ []) do
    record = create(parent, Keyword.get(opts, :state, :committed))

    for {method, amount} <- Keyword.get(opts, :payments, []) do
      generate(payment([{parent_key(parent), record.id}, method: method, amount: Decimal.new(amount)]))
    end

    if opts[:lowered], do: lower(record)

    Ash.load!(record, @fields, authorize?: false, reuse_values?: false)
  end

  defp create(:order, state) do
    tax_rate = generate(tax_rate())
    variant = generate(product_variant(product_id: generate(product(tax_rate_id: tax_rate.id)).id, price: "40.00"))

    order =
      generate(
        order(
          state: if(state == :uncommitted, do: :payment, else: :placed),
          fulfillment_status: if(state == :cancelled, do: :cancelled, else: :pending),
          fulfillment_option_id: generate(fulfillment_option(tax_rate_id: tax_rate.id)).id,
          quoted_fulfillment_fee: "0.00"
        )
      )

    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))
    order
  end

  defp create(:booking, state) do
    status =
      case state do
        :committed -> :confirmed
        :cancelled -> :cancelled
        :uncommitted -> :pending
      end

    generate(course_registration(status: status, seats: 2, amount: Decimal.new("80.00")))
  end

  defp lower(%Edenflowers.Orders.Order{} = order) do
    [line_item] = Ash.load!(order, :line_items, authorize?: false).line_items
    line_item |> Ash.Changeset.for_update(:set_quantity, %{quantity: 1}) |> Ash.update!(authorize?: false)
  end

  defp lower(registration), do: Edenflowers.Courses.remove_registration_seat!(registration, authorize?: false)

  defp parent_key(:order), do: :order_id
  defp parent_key(:booking), do: :course_registration_id

  defp record_payment(record, amount, method \\ :cash) do
    record
    |> Ash.Changeset.for_update(:record_payment, %{amount: amount, payment_method: method}, authorize?: false)
    |> Ash.update()
  end

  defp undo_payment(record, payment_id) do
    record
    |> Ash.Changeset.for_update(:undo_payment, %{payment_id: payment_id}, authorize?: false)
    |> Ash.update()
  end

  defp reload(record), do: Ash.load!(record, @fields, authorize?: false, reuse_values?: false)

  defp payments(record), do: Ash.load!(record, :payments, authorize?: false, reuse_values?: false).payments

  defp stripe_refund(payment_intent_id, cents) do
    %{
      id: "re_#{System.unique_integer([:positive])}",
      status: "succeeded",
      payment_intent: payment_intent_id,
      amount: cents
    }
  end

  defp unsettled_ids(:order), do: Enum.map(Edenflowers.Orders.list_unsettled_orders!(authorize?: false), & &1.id)

  defp unsettled_ids(:booking),
    do: Enum.map(Edenflowers.Courses.list_unsettled_registrations!(authorize?: false), & &1.id)

  defp assert_money(actual, expected), do: assert(Decimal.equal?(actual, expected), "#{actual} != #{expected}")

  for parent <- [:order, :booking] do
    describe "#{parent}" do
      @parent parent

      test "unpaid owes its total" do
        record = build(@parent)

        assert record.committed?
        assert_money(record.total_due, "80.00")
        assert_money(record.balance, "80.00")
        refute record.settled?
        assert_money(record.outside_stripe_refund, 0)
        refute record.stripe_refundable?
      end

      for payments <- [[stripe: "80.00"], [cash: "80.00"], [stripe: "50.00", mobilepay: "30.00"]] do
        test "paid in full by #{inspect(payments)} is settled" do
          record = build(@parent, payments: unquote(payments))

          assert_money(record.balance, 0)
          assert record.settled?
          refute record.refunded?
        end
      end

      test "part-paid owes the rest" do
        record = build(@parent, payments: [cash: "30.00"])

        assert_money(record.balance, "50.00")
        refute record.settled?
      end

      test "cancelled and never paid owes nothing" do
        record = build(@parent, state: :cancelled)

        assert_money(record.total_due, 0)
        assert_money(record.balance, 0)
        assert record.settled?
      end

      test "cancelled after paying by card is refunded through Stripe" do
        record = build(@parent, state: :cancelled, payments: [stripe: "80.00"])

        assert_money(record.balance, "-80.00")
        refute record.settled?
        assert record.stripe_refundable?
        assert_money(record.outside_stripe_refund, 0)
      end

      test "cancelled after paying cash is refunded by Jennie" do
        record = build(@parent, state: :cancelled, payments: [cash: "80.00"])

        assert_money(record.balance, "-80.00")
        refute record.stripe_refundable?
        assert_money(record.outside_stripe_refund, "80.00")
      end

      test "cancelled after paying by card and cash is refunded both ways" do
        record = build(@parent, state: :cancelled, payments: [stripe: "50.00", cash: "30.00"])

        assert_money(record.balance, "-80.00")
        assert record.stripe_refundable?
        assert_money(record.stripe_refund, "50.00")
        assert_money(record.outside_stripe_refund, "30.00")
      end

      test "cancelled and refunded in full is settled" do
        record = build(@parent, state: :cancelled, payments: [stripe: "80.00", stripe: "-80.00"])

        assert_money(record.balance, 0)
        assert record.settled?
        assert record.refunded?
      end

      test "refunded in full without being cancelled is settled though its balance reads the total" do
        record = build(@parent, payments: [stripe: "80.00", stripe: "-80.00"])

        assert record.refunded?
        assert record.settled?
        assert_money(record.balance, "80.00")
      end

      test "lowered after paying by card and cash owes the difference back" do
        record = build(@parent, lowered: true, payments: [stripe: "50.00", cash: "30.00"])

        assert_money(record.total_due, "40.00")
        assert_money(record.balance, "-40.00")
        refute record.settled?
        assert record.stripe_refundable?
        assert_money(record.stripe_refund, "40.00")
        assert_money(record.outside_stripe_refund, "30.00")
      end

      test "an uncommitted one owes nothing yet" do
        refute build(@parent, state: :uncommitted).committed?
      end

      test "the unsettled list holds what's still owed either way" do
        listed = [
          build(@parent),
          build(@parent, payments: [cash: "30.00"]),
          build(@parent, state: :cancelled, payments: [cash: "80.00"])
        ]

        left_out = [
          build(@parent, payments: [cash: "80.00"]),
          build(@parent, payments: [stripe: "80.00", stripe: "-80.00"]),
          build(@parent, state: :cancelled),
          build(@parent, state: :uncommitted)
        ]

        ids = unsettled_ids(@parent)
        for record <- listed, do: assert(record.id in ids)
        for record <- left_out, do: refute(record.id in ids)
      end

      for method <- [:cash, :mobilepay, :zettle, :zervant] do
        test "paying the whole balance by #{method} settles it" do
          record = build(@parent)

          assert {:ok, record} = record_payment(record, "80.00", unquote(method))

          assert record.settled?
          assert [%{method: unquote(method), paid_at: %DateTime{}} = payment] = payments(record)
          assert_money(payment.amount, "80.00")
        end
      end

      test "a part-payment leaves the rest owed" do
        {:ok, record} = record_payment(build(@parent), "30.00")

        assert_money(record.balance, "50.00")
      end

      test "a payment larger than the balance is refused" do
        record = build(@parent)

        assert {:error, error} = record_payment(record, "80.01")
        assert Exception.message(error) =~ "That's more than is owed"
        assert payments(record) == []
      end

      test "a Stripe payment can't be recorded by hand" do
        assert {:error, error} = record_payment(build(@parent), "80.00", :stripe)
        assert Exception.message(error) =~ "is recorded from Stripe"
      end

      test "a payment on a cancelled one is refused" do
        assert {:error, _error} = record_payment(build(@parent, state: :cancelled), "10.00")
        assert {:error, _error} = record_payment(build(@parent, state: :cancelled, payments: [cash: "80.00"]), "10.00")
      end

      test "a payment on an uncommitted one is refused" do
        assert {:error, error} = record_payment(build(@parent, state: :uncommitted), "10.00")
        assert Exception.message(error) =~ "can't be recorded before it's placed or confirmed"
      end

      test "a refund of what's owed back, up to what was paid outside Stripe, settles it" do
        record = build(@parent, state: :cancelled, payments: [cash: "80.00"])

        assert {:ok, record} = record_payment(record, Decimal.negate(record.outside_stripe_refund), :mobilepay)
        assert record.settled?
      end

      test "a refund larger than what was paid outside Stripe is refused" do
        record = build(@parent, state: :cancelled, payments: [stripe: "50.00", cash: "30.00"])

        assert {:error, error} = record_payment(record, "-30.01")
        assert Exception.message(error) =~ "is more than was paid outside Stripe"
      end

      test "a refund larger than what's owed back is refused" do
        record = build(@parent, lowered: true, payments: [cash: "80.00"])

        assert {:error, error} = record_payment(record, "-40.01")
        assert Exception.message(error) =~ "That's more than is owed back"
      end

      test "a goodwill refund on a settled one is refused" do
        record = build(@parent, payments: [cash: "80.00"])

        assert {:error, error} = record_payment(record, "-10.00")
        assert Exception.message(error) =~ "Lower the order or cancel it before refunding"
      end

      test "a refund while something is still to collect is refused" do
        record = build(@parent, payments: [cash: "30.00"])

        assert {:error, error} = record_payment(record, "-30.00")
        assert Exception.message(error) =~ "Lower the order or cancel it before refunding"
      end

      test "undoing a whole payment recorded by mistake leaves the total owed again" do
        {:ok, record} = record_payment(build(@parent), "80.00", :zettle)
        [payment] = payments(record)

        assert {:ok, record} = undo_payment(record, payment.id)

        assert_money(record.balance, "80.00")
        refute record.settled?
        refute record.refunded?
        undo = Enum.find(payments(record), & &1.reverses_payment_id)
        assert %{method: :zettle, reverses_payment_id: reversed} = undo
        assert reversed == payment.id
        assert_money(undo.amount, "-80.00")
      end

      test "undoing a refund recorded by mistake owes it back again" do
        record = build(@parent, state: :cancelled, payments: [cash: "80.00", cash: "-80.00"])
        refund = Enum.find(payments(record), &Decimal.negative?(&1.amount))

        assert {:ok, record} = undo_payment(record, refund.id)
        assert_money(record.balance, "-80.00")
      end

      test "a payment is undone once" do
        {:ok, record} = record_payment(build(@parent), "30.00")
        [payment] = payments(record)

        assert {:ok, record} = undo_payment(record, payment.id)
        assert {:error, _error} = undo_payment(record, payment.id)

        undo = Enum.find(payments(record), & &1.reverses_payment_id)
        assert {:error, error} = undo_payment(record, undo.id)
        assert Exception.message(error) =~ "can't be undone"
      end

      test "a Stripe payment, or another record's payment, can't be undone" do
        record = build(@parent, payments: [stripe: "80.00"])
        [stripe] = payments(record)
        [other] = payments(build(@parent, payments: [cash: "80.00"]))

        assert {:error, _error} = undo_payment(record, stripe.id)
        assert {:error, _error} = undo_payment(record, other.id)
      end

      test "recording cancels the open PaymentIntent, which charged the old balance" do
        record = build(@parent) |> Ash.Seed.update!(%{payment_intent_id: "pi_open"}) |> reload()
        expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_open"} -> {:ok, %{id: "pi_open"}} end)

        assert {:ok, record} = record_payment(record, "30.00")
        assert record.payment_intent_id == nil
      end

      test "a Stripe refund is recorded once, however often it's delivered" do
        record = build(@parent, state: :cancelled)

        generate(
          payment([{parent_key(@parent), record.id}, amount: Decimal.new("80.00"), payment_intent_id: "pi_paid"])
        )

        refund = stripe_refund("pi_paid", 8_000)

        assert {:ok, :recorded} = Payments.record_stripe_refund(refund)
        assert {:ok, :already_recorded} = Payments.record_stripe_refund(refund)

        assert reload(record).settled?
      end

      test "a Stripe refund beyond what was owed back is recorded, leaving a balance to collect" do
        record = build(@parent, lowered: true)

        generate(
          payment([{parent_key(@parent), record.id}, amount: Decimal.new("80.00"), payment_intent_id: "pi_paid"])
        )

        assert {:ok, :recorded} = Payments.record_stripe_refund(stripe_refund("pi_paid", 6_000))

        assert_money(reload(record).balance, "20.00")
      end
    end
  end
end

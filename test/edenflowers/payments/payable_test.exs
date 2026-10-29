defmodule Edenflowers.Payments.PayableTest do
  @moduledoc """
  Shared ledger arithmetic and validation run against an order. Resource
  integration, cancellation and settlement run against both orders and bookings.
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
    :to_collect?,
    :to_refund?,
    :amount_held,
    :refundable?
  ]

  # An order or booking for 80.00, paid with `payments` like `[stripe: "50.00", cash: "30.00"]`.
  # `lowered: true` drops it to 40.00 after it was paid.
  defp build(parent, opts \\ []) do
    record = create(parent, Keyword.get(opts, :state, :committed))

    for {method, amount} <- Keyword.get(opts, :payments, []) do
      generate(payment([{parent_key(parent), record.id}, method: method, amount: Decimal.new(amount)]))
    end

    if opts[:lowered], do: lower(record)
    if opts[:kept], do: Ash.Seed.update!(record, %{kept_amount: Decimal.new(opts[:kept])})

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
          fulfillment_date: ~D[2026-11-14],
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

  defp refund(record, amount, method \\ :cash, note \\ nil) do
    record
    |> Ash.Changeset.for_update(:refund, %{amount: amount, payment_method: method, note: note}, authorize?: false)
    |> Ash.update()
  end

  defp stripe_payment(parent, record, payment_intent_id, amount, paid_at) do
    generate(
      payment([
        {parent_key(parent), record.id},
        amount: Decimal.new(amount),
        payment_intent_id: payment_intent_id,
        paid_at: paid_at
      ])
    )
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

  defp cancel(record, input) do
    record
    |> Ash.Changeset.for_update(:cancel, input, authorize?: false)
    |> Ash.update()
  end

  defp cancelled?(record), do: Ash.load!(record, :cancelled?, authorize?: false, reuse_values?: false).cancelled?

  defp with_email(%Edenflowers.Orders.Order{} = order),
    do: Ash.Seed.update!(order, %{customer_email: "maria@example.com"})

  defp with_email(registration), do: registration

  defp expect_stripe_refund(payment_intent_id, cents) do
    StripeAPI.Mock
    |> stub(:list_refunds, fn _pi -> {:ok, []} end)
    |> expect(:create_refund, fn ^payment_intent_id, ^cents, _key, %{"reason" => "owed"} ->
      {:ok, stripe_refund(payment_intent_id, cents)}
    end)
  end

  defp unsettled_ids(:order), do: Enum.map(Edenflowers.Orders.list_unsettled_orders!(authorize?: false), & &1.id)

  defp unsettled_ids(:booking),
    do: Enum.map(Edenflowers.Courses.list_unsettled_registrations!(authorize?: false), & &1.id)

  defp assert_money(actual, expected), do: assert(Decimal.equal?(actual, expected), "#{actual} != #{expected}")

  describe "shared ledger" do
    for payments <- [[stripe: "80.00"], [cash: "80.00"], [stripe: "50.00", mobilepay: "30.00"]] do
      test "paid in full by #{inspect(payments)} is settled" do
        record = build(:order, payments: unquote(payments))

        assert_money(record.balance, 0)
        assert record.settled?
        refute record.refunded?
      end
    end

    test "part-paid owes the rest" do
      record = build(:order, payments: [cash: "30.00"])

      assert_money(record.balance, "50.00")
      refute record.settled?
      assert record.to_collect?
      refute record.to_refund?
    end

    test "a part-payment leaves the rest owed" do
      {:ok, record} = record_payment(build(:order), "30.00")

      assert_money(record.balance, "50.00")
    end

    test "a payment larger than the balance is refused" do
      record = build(:order)

      assert {:error, error} = record_payment(record, "80.01")
      assert Exception.message(error) =~ "That's more than is owed"
      assert payments(record) == []
    end

    test "a Stripe payment can't be recorded by hand" do
      assert {:error, error} = record_payment(build(:order), "80.00", :stripe)
      assert Exception.message(error) =~ "is recorded from Stripe"
    end

    test "a negative payment is refused: money handed back is a refund" do
      assert {:error, _error} = record_payment(build(:order, payments: [cash: "80.00"]), "-10.00")
    end

    test "a refund keeps its reason" do
      {:ok, record} = refund(build(:order, payments: [cash: "80.00"]), "10.00", :cash, "Wilted early")

      assert [%{note: "Wilted early"}] = Enum.filter(payments(record), &Decimal.negative?(&1.amount))
    end

    test "a refund above what was paid outside Stripe is refused outside Stripe" do
      record = build(:order, payments: [stripe: "50.00", cash: "30.00"])

      assert {:error, error} = refund(record, "30.01")
      assert Exception.message(error) =~ "That's more than was paid outside Stripe"
    end

    test "a refund by a method holding nothing is refused" do
      record = build(:order, state: :cancelled, payments: [cash: "80.00"])

      assert {:error, error} = refund(record, "10.00", :stripe)
      assert Exception.message(error) =~ "That's more than was paid through Stripe"
    end

    test "a refund while something is to collect is refused" do
      record = build(:order, payments: [cash: "30.00"])
      refute record.refundable?

      assert {:error, error} = refund(record, "10.00")
      assert Exception.message(error) =~ "Collect what's owed before refunding"
    end

    test "a refund through Stripe above what was paid through it is refused" do
      record = build(:order, payments: [stripe: "50.00", cash: "30.00"])

      assert {:error, error} = refund(record, "50.01", :stripe)
      assert Exception.message(error) =~ "That's more than was paid through Stripe."
    end
  end

  for parent <- [:order, :booking] do
    describe "#{parent}" do
      @parent parent

      test "unpaid owes its total" do
        record = build(@parent)

        assert record.committed?
        assert_money(record.total_due, "80.00")
        assert_money(record.balance, "80.00")
        refute record.settled?
      end

      test "cancelled and never paid owes nothing" do
        record = build(@parent, state: :cancelled)

        assert_money(record.total_due, 0)
        assert_money(record.balance, 0)
        assert record.settled?
      end

      test "cancelled with money still held owes it back" do
        record = build(@parent, state: :cancelled, payments: [stripe: "50.00", cash: "30.00"])

        assert_money(record.balance, "-80.00")
        refute record.settled?
        assert record.to_refund?
        refute record.to_collect?
        assert record.refundable?
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
        refute record.to_collect?
        refute record.to_refund?
      end

      test "lowered after paying by card and cash owes the difference back" do
        record = build(@parent, lowered: true, payments: [stripe: "50.00", cash: "30.00"])

        assert_money(record.total_due, "40.00")
        assert_money(record.balance, "-40.00")
        refute record.settled?
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

      for method <- if(parent == :order, do: [:cash, :mobilepay, :zettle, :zervant], else: [:cash]) do
        test "paying the whole balance by #{method} settles it" do
          record = build(@parent)

          assert {:ok, record} = record_payment(record, "80.00", unquote(method))

          assert record.settled?
          assert [%{method: unquote(method), paid_at: %DateTime{}} = payment] = payments(record)
          assert_money(payment.amount, "80.00")
        end
      end

      test "a refusal is in Jennie's language" do
        Gettext.put_locale(EdenflowersWeb.Gettext, "fi")

        assert {:error, error} = record_payment(build(@parent), "80.01")
        assert Exception.message(error) =~ "Summa on suurempi kuin maksettavaa on jäljellä."
      end

      test "a payment on a cancelled one is refused" do
        assert {:error, _error} = record_payment(build(@parent, state: :cancelled), "10.00")

        assert {:error, _error} =
                 record_payment(build(@parent, state: :cancelled, payments: [cash: "80.00"]), "10.00")
      end

      test "a payment on an uncommitted one is refused" do
        assert {:error, error} = record_payment(build(@parent, state: :uncommitted), "10.00")
        assert Exception.message(error) =~ "Nothing can be recorded until it's placed or confirmed"
      end

      test "undoing a whole payment recorded by mistake leaves the total owed again" do
        record = build(@parent, payments: [zettle: "80.00"])
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

      test "a payment already refunded can't be undone" do
        record = build(@parent, state: :cancelled, payments: [cash: "80.00", cash: "-80.00"])
        payment = Enum.find(payments(record), &Decimal.positive?(&1.amount))

        assert {:error, error} = undo_payment(record, payment.id)
        assert Exception.message(error) =~ "Its money was since refunded"
        assert reload(record).settled?
      end

      test "a payment is undone once" do
        record = build(@parent, payments: [cash: "30.00"])
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

        expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_open"} ->
          {:ok, %{id: "pi_open", status: "canceled"}}
        end)

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

      test "a Stripe refund on a settled one is goodwill and leaves it settled" do
        record = build(@parent)

        generate(
          payment([{parent_key(@parent), record.id}, amount: Decimal.new("80.00"), payment_intent_id: "pi_paid"])
        )

        assert {:ok, :recorded} = Payments.record_stripe_refund(stripe_refund("pi_paid", 3_000))

        record = reload(record)
        assert record.settled?
        assert_money(record.balance, 0)

        assert [%{goodwill: true, method: :stripe, note: nil} = refund] =
                 Enum.filter(payments(record), & &1.stripe_refund_id)

        assert_money(refund.amount, "-30.00")
        refute record.id in unsettled_ids(@parent)
      end

      test "a Stripe refund beyond what was owed back settles what was owed and marks the rest goodwill" do
        record = build(@parent, lowered: true)

        generate(
          payment([{parent_key(@parent), record.id}, amount: Decimal.new("80.00"), payment_intent_id: "pi_paid"])
        )

        assert {:ok, :recorded} = Payments.record_stripe_refund(stripe_refund("pi_paid", 6_000))

        record = reload(record)
        assert record.settled?
        refunds = record |> payments() |> Enum.filter(& &1.stripe_refund_id) |> Enum.sort_by(& &1.goodwill)
        assert [%{goodwill: false} = owed, %{goodwill: true} = goodwill] = refunds
        assert_money(owed.amount, "-40.00")
        assert_money(goodwill.amount, "-20.00")

        assert {:ok, :already_recorded} =
                 Payments.record_stripe_refund(%{stripe_refund("pi_paid", 6_000) | id: owed.stripe_refund_id})
      end

      test "a refund of what's owed back is an ordinary refund and settles it" do
        record = build(@parent, state: :cancelled, payments: [cash: "80.00"])

        assert {:ok, record} = refund(record, "80.00", :mobilepay)

        assert record.settled?
        assert [%{goodwill: false, method: :mobilepay}] = Enum.filter(payments(record), &Decimal.negative?(&1.amount))
      end

      test "a refund on a cancelled one pays back what's owed first" do
        record = build(@parent, state: :cancelled, payments: [cash: "80.00"])

        assert {:ok, record} = refund(record, "30.00")

        assert_money(record.balance, "-50.00")
        assert [%{goodwill: false}] = Enum.filter(payments(record), &Decimal.negative?(&1.amount))
      end

      test "a refund beyond what's owed back marks the rest goodwill and leaves it settled" do
        record = build(@parent, lowered: true, payments: [cash: "80.00"])

        assert {:ok, record} = refund(record, "50.00")

        assert record.settled?
        refunds = record |> payments() |> Enum.filter(&Decimal.negative?(&1.amount)) |> Enum.sort_by(& &1.goodwill)
        assert [%{goodwill: false} = owed, %{goodwill: true} = goodwill] = refunds
        assert_money(owed.amount, "-40.00")
        assert_money(goodwill.amount, "-10.00")
      end

      test "a part refund on a settled one leaves it settled" do
        record = build(@parent, payments: [cash: "80.00"])
        assert record.refundable?

        assert {:ok, record} = refund(record, "30.00")

        assert record.settled?
        refute record.refunded?
        assert_money(record.balance, 0)
        assert_money(record.amount_held, "50.00")
      end

      test "a refund of everything received reads refunded" do
        {:ok, record} = refund(build(@parent, payments: [mobilepay: "80.00"]), "80.00", :mobilepay)

        assert record.refunded?
        assert record.settled?
        refute reload(record).refundable?
      end

      test "a refund above what was received is refused" do
        record = build(@parent, payments: [cash: "80.00"])
        {:ok, record} = refund(record, "30.00")

        assert {:error, error} = refund(record, "50.01")
        assert Exception.message(error) =~ "That's more than was received"
      end

      for {payments, methods, default} <- [
            {[stripe: "80.00"], [:stripe], :stripe},
            {[cash: "50.00", mobilepay: "30.00"], [:zettle, :mobilepay, :cash, :zervant], :cash},
            {[stripe: "50.00", cash: "30.00"], [:stripe, :zettle, :mobilepay, :cash, :zervant], :stripe},
            {[stripe: "80.00", stripe: "-80.00"], [], nil},
            {[stripe: "50.00", cash: "30.00", stripe: "-50.00"], [:zettle, :mobilepay, :cash, :zervant], :cash}
          ] do
        test "paid #{inspect(payments)} refunds by #{inspect(methods)}, starting at #{inspect(default)}" do
          record =
            build(@parent, payments: unquote(payments))
            |> Ash.load!([:refund_methods, :default_refund_method], authorize?: false)

          assert record.refund_methods == unquote(methods)
          assert record.default_refund_method == unquote(default)
        end
      end

      test "a refund hands back money kept on a cancelled one" do
        record = build(@parent, state: :cancelled, payments: [cash: "80.00"], kept: "80.00")
        assert record.refundable?

        assert {:ok, record} = refund(record, "30.00")
        assert record.settled?
        assert_money(record.amount_held, "50.00")
      end

      test "a goodwill refund can be undone" do
        {:ok, record} = refund(build(@parent, payments: [cash: "80.00"]), "80.00")
        refund = Enum.find(payments(record), & &1.goodwill)

        assert {:ok, record} = undo_payment(record, refund.id)

        refute record.refunded?
        assert record.settled?
        assert_money(record.amount_held, "80.00")
        assert %{goodwill: true} = Enum.find(payments(record), & &1.reverses_payment_id)
      end

      test "lowered after a goodwill refund owes back only what's still held above the price" do
        {:ok, record} = refund(build(@parent, payments: [cash: "80.00"]), "30.00")

        lower(record)

        assert_money(reload(record).balance, "-10.00")
      end

      test "a refund through Stripe is spread over the Stripe payments, newest first" do
        record = build(@parent)
        stripe_payment(@parent, record, "pi_old", "50.00", ~U[2026-10-01 10:00:00Z])
        stripe_payment(@parent, record, "pi_new", "30.00", ~U[2026-10-02 10:00:00Z])

        StripeAPI.Mock
        |> stub(:list_refunds, fn _pi -> {:ok, []} end)
        |> expect(:create_refund, fn "pi_new", 3_000, _key, %{"reason" => "refund", "note" => "Late"} ->
          {:ok, stripe_refund("pi_new", 3_000)}
        end)
        |> expect(:create_refund, fn "pi_old", 1_500, _key, %{"reason" => "refund", "note" => "Late"} ->
          {:ok, stripe_refund("pi_old", 1_500)}
        end)

        assert {:ok, _record} = refund(reload(record), "45.00", :stripe, "Late")

        record = reload(record)
        assert record.settled?
        assert_money(record.amount_held, "35.00")

        assert record
               |> payments()
               |> Enum.filter(& &1.stripe_refund_id)
               |> Enum.all?(&(&1.goodwill and &1.note == "Late"))
      end

      test "a refund emails the customer, unless Jennie unticks it" do
        record = build(@parent, payments: [cash: "80.00"])

        record =
          if @parent == :order, do: Ash.Seed.update!(record, %{customer_email: "maria@example.com"}), else: record

        record
        |> Ash.Changeset.for_update(:refund, %{amount: "10.00", payment_method: :cash, email_customer?: false},
          authorize?: false
        )
        |> Ash.update!()

        refute_enqueued(worker: Edenflowers.Payments.Workers.SendRefundedEmail)

        {:ok, _record} = refund(record, "10.00", :cash, "Sorry")
        [job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendRefundedEmail)
        assert %{"amount" => "10.00", "payment_method" => "cash", "note" => "Sorry"} = job.args
        assert :ok = perform_job(Edenflowers.Payments.Workers.SendRefundedEmail, job.args)
      end

      test "cancelling refunds through Stripe all but what Jennie keeps, and emails the customer" do
        record = with_email(build(@parent))
        stripe_payment(@parent, record, "pi_paid", "80.00", ~U[2026-10-01 10:00:00Z])
        expect_stripe_refund("pi_paid", 6_000)

        assert {:ok, cancelled} = cancel(record, %{refund: "60.00", held: "80.00"})

        assert cancelled.cancelled_at
        assert cancelled.cancellation_emailed_to
        assert_money(cancelled.kept_amount, "20.00")
        assert reload(cancelled).settled?
        assert [job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendCancelledEmail)
        assert %{"refunded_amount" => "60.00", "to_return" => "0.00"} = job.args
        assert :ok = perform_job(Edenflowers.Payments.Workers.SendCancelledEmail, job.args)

        Swoosh.TestAssertions.assert_email_sent(fn email ->
          assert email.bcc == [{"Jennie", "info+copy@edenflowers.fi"}]
        end)
      end

      test "cancelling without a refund amount refunds everything held" do
        record = build(@parent, payments: [cash: "80.00"])

        assert {:ok, cancelled} = cancel(record, %{})

        assert_money(cancelled.kept_amount, "0")
        assert_money(reload(cancelled).balance, "-80.00")
      end

      test "a cancel retried after Stripe refunded keeps the same amount and refunds nothing twice" do
        record = build(@parent)
        stripe_payment(@parent, record, "pi_paid", "80.00", ~U[2026-10-01 10:00:00Z])

        generate(
          payment([{parent_key(@parent), record.id}, amount: Decimal.new("-60.00"), stripe_refund_id: "re_first"])
        )

        StripeAPI.Mock
        |> stub(:list_refunds, fn _pi -> {:ok, []} end)
        |> expect(:create_refund, 0, fn _pi, _cents, _key, _metadata -> flunk("refunded twice") end)

        assert {:ok, cancelled} = cancel(record, %{refund: "60.00", held: "80.00"})
        assert_money(cancelled.kept_amount, "20.00")
        assert reload(cancelled).settled?
      end

      test "money that arrived after Jennie opened the drawer refuses the cancel" do
        record = build(@parent, payments: [cash: "80.00"])

        assert {:error, error} = cancel(record, %{refund: "50.00", held: "50.00"})
        assert Exception.message(error) =~ "This changed while you had it open"
        refute cancelled?(record)
      end

      test "a refund outside nothing to what was held is refused" do
        record = build(@parent, payments: [cash: "80.00"])

        for refund <- ["80.01", "-1.00"] do
          assert {:error, error} = cancel(record, %{refund: refund, held: "80.00"})
          assert Exception.message(error) =~ "Enter an amount from 0 € to 80,00 €."
        end
      end

      test "money paid in person is left for Jennie to hand back" do
        record = with_email(build(@parent, payments: [cash: "30.00"]))
        stripe_payment(@parent, record, "pi_paid", "50.00", ~U[2026-10-01 10:00:00Z])
        expect_stripe_refund("pi_paid", 5_000)

        assert {:ok, cancelled} = cancel(record, %{})

        assert_money(reload(cancelled).balance, "-30.00")
        assert [job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendCancelledEmail)
        assert %{"refunded_amount" => "50.00", "to_return" => "30.00"} = job.args
      end

      test "a refund Stripe refuses cancels nothing and emails nobody" do
        record = with_email(build(@parent))
        stripe_payment(@parent, record, "pi_paid", "80.00", ~U[2026-10-01 10:00:00Z])

        StripeAPI.Mock
        |> stub(:list_refunds, fn _pi -> {:ok, []} end)
        |> expect(:create_refund, fn _pi, _cents, _key, _metadata -> {:error, :charge_disputed} end)

        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, error} = cancel(record, %{})
          assert Exception.message(error) =~ "Stripe refused the refund"
        end)

        refute cancelled?(record)
        refute_enqueued(worker: Edenflowers.Payments.Workers.SendCancelledEmail)
      end

      test "unticking the email emails nobody" do
        record = with_email(build(@parent))

        assert {:ok, cancelled} = cancel(record, %{email_customer?: false})

        assert cancelled.cancellation_emailed_to == nil
        refute_enqueued(worker: Edenflowers.Payments.Workers.SendCancelledEmail)
      end

      test "a copy loaded before someone else cancelled it can't be cancelled again" do
        record = build(@parent)
        assert {:ok, _cancelled} = cancel(record, %{email_customer?: false})

        assert {:error, error} = cancel(record, %{})
        assert Exception.message(error) =~ "This changed while you had it open"
      end

      test "an uncommitted one can't be cancelled" do
        assert {:error, _error} = cancel(build(@parent, state: :uncommitted), %{})
      end
    end
  end
end

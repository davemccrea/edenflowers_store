defmodule Edenflowers.Payments.PayableTest do
  @moduledoc """
  Every case runs against an order and a course booking, which is what keeps
  the two working out what's owed the same way.
  """
  use Edenflowers.DataCase, async: true

  import Generator

  @fields [
    :total_due,
    :committed?,
    :amount_paid,
    :paid_outside_stripe,
    :balance,
    :refunded?,
    :settled?,
    :outside_stripe_refund,
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
        assert_money(record.outside_stripe_refund, "30.00")
      end

      test "an uncommitted one owes nothing yet" do
        refute build(@parent, state: :uncommitted).committed?
      end
    end
  end
end

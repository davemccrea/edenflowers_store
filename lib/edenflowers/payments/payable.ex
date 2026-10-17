defmodule Edenflowers.Payments.Payable do
  @moduledoc """
  What's owed on an order or a course booking, worked out once from its
  `Payment` rows (ADR 0002), so both read the same.

  The including resource supplies:

    * `has_many :payments`
    * `calculate :total_due`: what it's still to be paid for, 0 once cancelled.
    * `calculate :committed?`: whether money is owed on it at all, so not an
      unplaced cart or a booking still holding its seats while the customer pays.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

  calculations do
    # Positive is still to collect, negative is to refund.
    calculate :balance, :decimal, expr(total_due - amount_paid)

    calculate :refunded?, :boolean, expr(exists(payments, amount > 0) and amount_paid <= 0)

    # A record refunded in Stripe without being cancelled reads as owed again
    # by its balance, but is settled.
    calculate :settled?, :boolean, expr(balance == 0 or refunded?)

    # Money paid through Stripe goes back through Stripe, so Jennie can only
    # hand back what she took herself.
    calculate :outside_stripe_refund,
              :decimal,
              expr(
                cond do
                  balance >= 0 -> 0
                  -balance < paid_outside_stripe -> -balance
                  true -> paid_outside_stripe
                end
              )

    calculate :stripe_refundable?, :boolean, expr(balance < 0 and amount_paid > paid_outside_stripe)
  end

  aggregates do
    sum :amount_paid, :payments, :amount, default: Decimal.new("0")
    sum :paid_outside_stripe, :payments, :amount, filter: expr(method != :stripe), default: Decimal.new("0")
  end
end

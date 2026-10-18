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

  alias Edenflowers.Payments.Changes
  alias Edenflowers.Payments.Validations

  actions do
    # Money Jennie took or handed back by any method except Stripe.
    update :record_payment do
      argument :amount, :decimal, allow_nil?: false, constraints: [scale: 2]
      argument :payment_method, Edenflowers.Payments.PaymentMethod, allow_nil?: false

      validate argument_does_not_equal(:payment_method, :stripe), message: "is recorded from Stripe"
      validate Validations.Recordable
      # A payment link charges the balance this changes; visiting it again
      # opens a PaymentIntent for whatever is left.
      change Changes.CancelOpenPaymentIntent
      change {Changes.RecordPayment, amount: :amount}
      require_atomic? false
    end

    # Takes back a payment Jennie recorded by mistake, once, by recording the
    # opposite amount against it. A refund on something that still stands
    # otherwise has to wait until it's lowered (Validations.Recordable).
    update :undo_payment do
      argument :payment_id, :uuid, allow_nil?: false
      argument :amount, :decimal, public?: false
      argument :payment_method, Edenflowers.Payments.PaymentMethod, public?: false
      argument :reverses_payment_id, :uuid, public?: false

      change Changes.UndoPayment
      # Undoing a payment whose money was since handed back would leave it owed again.
      validate {Validations.Recordable, undo?: true}
      change Changes.CancelOpenPaymentIntent
      change {Changes.RecordPayment, amount: :amount}
      require_atomic? false
    end

    # From Stripe's refund webhook, so a refund Jennie makes in the Stripe
    # dashboard shows up without her entering it again. Recorded whatever it
    # is, because the money moved; one beyond what was owed back leaves a
    # balance to collect.
    update :record_stripe_refund do
      argument :stripe_refund_id, :string, allow_nil?: false
      argument :amount, :decimal, allow_nil?: false, constraints: [max: 0, scale: 2]
      change {Changes.RecordPayment, method: :stripe, amount: :amount}
      require_atomic? false
    end
  end

  calculations do
    # Positive is still to collect, negative is to refund.
    calculate :balance, :decimal, expr(total_due - amount_paid)

    # An undone payment and its undo don't count as taking and handing back money.
    calculate :refunded?,
              :boolean,
              expr(
                exists(payments, amount > 0 and is_nil(reverses_payment_id) and not exists(reversal, true)) and
                  amount_paid <= 0
              )

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

    # What Payments.refund_balance/1 sends back: the balance, as far as Stripe payments cover it.
    calculate :stripe_refund,
              :decimal,
              expr(
                cond do
                  balance >= 0 or amount_paid <= paid_outside_stripe -> 0
                  -balance < amount_paid - paid_outside_stripe -> -balance
                  true -> amount_paid - paid_outside_stripe
                end
              )
  end

  aggregates do
    sum :amount_paid, :payments, :amount, default: Decimal.new("0")
    sum :paid_outside_stripe, :payments, :amount, filter: expr(method != :stripe), default: Decimal.new("0")
  end
end

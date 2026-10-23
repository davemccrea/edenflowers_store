defmodule Edenflowers.Payments.Payable do
  @moduledoc """
  What's owed on an order or a course booking, worked out once from its
  `Payment` rows (ADR 0002), so both read the same.

  The including resource supplies:

    * an `:email_receipt` update action that emails the customer their receipt

    * `has_many :payments`
    * `calculate :total_due`: what it's still to be paid for. Once cancelled,
      that's `kept_amount`.
    * `calculate :committed?`: whether money is owed on it at all, so not an
      unplaced cart or a booking still holding its seats while the customer pays.
    * `calculate :cancelled?`
    * `calculate :cancellable?`: whether it can be cancelled now
    * `customer_email`: who's told about cancels and refunds, or nil
    * a `:for_customer_email` read action that loads what `Email.cancelled/3`
      and `Email.refunded/2` need
    * `cancelled_at` and `cancellation_emailed_to` attributes, and a `:cancel`
      update action with `Changes.Cancel` and its `refund`, `held` and
      `email_customer?` arguments
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Edenflowers.Payments.Changes
  alias Edenflowers.Payments.Validations

  attributes do
    # Money not handed back when it was cancelled: what Jennie chose to keep.
    attribute :kept_amount, :decimal, allow_nil?: false, default: 0, constraints: [min: 0, scale: 2]
  end

  actions do
    update :add_payment_intent_id do
      accept [:payment_intent_id]
      validate Validations.PaymentIntentNotSet
      validate Validations.Payable
    end

    update :mark_payment_cancelled do
      argument :payment_intent_id, :string, allow_nil?: false
      validate Validations.MatchesPaymentIntent
      change set_attribute(:payment_intent_id, nil)
    end

    # Each resource triggers it with its own `where`.
    update :reconcile_payment do
      accept []
      transaction? false
      require_atomic? false
      change Changes.Reconcile
    end

    # Money Jennie took by any method except Stripe.
    update :record_payment do
      argument :amount, :decimal, allow_nil?: false, constraints: [greater_than: 0, scale: 2]
      argument :payment_method, Edenflowers.Payments.PaymentMethod, allow_nil?: false
      argument :email_receipt?, :boolean, default: false
      argument :message, :string

      validate argument_does_not_equal(:payment_method, :stripe), message: "is recorded from Stripe"
      validate Validations.Recordable
      # A payment link charges the balance this changes; visiting it again
      # opens a PaymentIntent for whatever is left.
      change Changes.CancelOpenPaymentIntent
      change {Changes.RecordPayment, amount: :amount}
      change Changes.EmailReceipt, where: [argument_equals(:email_receipt?, true)]
      require_atomic? false
    end

    # Money Jennie hands back, by any method, with or without cancelling.
    # What was owed back is an ordinary refund and the rest is goodwill, so
    # the record stays settled either way.
    update :refund do
      argument :amount, :decimal, allow_nil?: false, constraints: [greater_than: 0, scale: 2]
      argument :payment_method, Edenflowers.Payments.PaymentMethod, allow_nil?: false
      argument :note, :string
      argument :email_customer?, :boolean, default: true
      argument :refund, :decimal, public?: false
      argument :owed_back, :decimal, public?: false
      argument :goodwill_refund, :decimal, public?: false

      validate Validations.Refundable
      change Changes.Refund
      change {Changes.SplitOffGoodwill, amount: :refund}
      change {Changes.RecordPayment, amount: :owed_back, goodwill: false}, where: [present(:owed_back)]
      change {Changes.RecordPayment, amount: :goodwill_refund, goodwill: true}, where: [present(:goodwill_refund)]
      change Changes.SendRefundedEmail, where: [argument_equals(:email_customer?, true)]
      require_atomic? false
    end

    # Takes back a payment Jennie recorded by mistake, once, by recording the
    # opposite amount against it.
    update :undo_payment do
      argument :payment_id, :uuid, allow_nil?: false
      argument :amount, :decimal, public?: false
      argument :payment_method, Edenflowers.Payments.PaymentMethod, public?: false
      argument :reverses_payment_id, :uuid, public?: false
      argument :goodwill, :boolean, public?: false

      change Changes.UndoPayment
      # Undoing a payment whose money was since handed back would leave it owed again.
      validate {Validations.Recordable, undo?: true}
      change Changes.CancelOpenPaymentIntent
      change {Changes.RecordPayment, amount: :amount}
      require_atomic? false
    end

    # From Stripe's refund webhook, so a refund Jennie makes in the Stripe
    # dashboard shows up without her entering it again. Recorded whatever it
    # is, because the money moved. `goodwill` says what a refund made here
    # was; for one made in the dashboard, the part beyond what was owed back
    # is goodwill, recorded as its own payment.
    update :record_stripe_refund do
      argument :stripe_refund_id, :string, allow_nil?: false
      argument :amount, :decimal, allow_nil?: false, constraints: [max: 0, scale: 2]
      argument :goodwill, :boolean
      argument :note, :string
      argument :owed_back, :decimal, public?: false
      argument :goodwill_refund, :decimal, public?: false

      change Changes.SplitOffGoodwill

      change {Changes.RecordPayment, method: :stripe, amount: :owed_back, goodwill: false},
        where: [present(:owed_back)]

      change {Changes.RecordPayment, method: :stripe, amount: :goodwill_refund, goodwill: true},
        where: [present(:goodwill_refund)]

      require_atomic? false
    end
  end

  calculations do
    # Positive is still to collect, negative is to refund. A goodwill refund
    # leaves it alone while the price stands, but once the price drops below
    # what was paid, only money still held above it is owed back.
    calculate :balance,
              :decimal,
              expr(
                cond do
                  total_due >= amount_paid -> total_due - amount_paid
                  total_due >= amount_held -> 0
                  true -> total_due - amount_held
                end
              )

    # An undone payment and its undo don't count as taking and handing back money.
    calculate :refunded?,
              :boolean,
              expr(
                exists(payments, amount > 0 and is_nil(reverses_payment_id) and not exists(reversal, true)) and
                  amount_held <= 0
              )

    # What a PaymentIntent can charge.
    calculate :payable?, :boolean, expr(balance > 0 and not refunded?)

    # A record refunded in Stripe without being cancelled reads as owed again
    # by its balance, but is settled.
    calculate :settled?, :boolean, expr(balance == 0 or refunded?)

    # Whether Jennie can hand money back (Validations.Refundable).
    calculate :refundable?, :boolean, expr(committed? and balance <= 0 and amount_held > 0)
  end

  aggregates do
    # What the customer paid for what was sold, so not goodwill refunds.
    sum :amount_paid, :payments, :amount, filter: expr(not goodwill), default: Decimal.new("0")
    # The money still with us.
    sum :amount_held, :payments, :amount, default: Decimal.new("0")
    sum :paid_outside_stripe, :payments, :amount, filter: expr(method != :stripe), default: Decimal.new("0")
    sum :paid_through_stripe, :payments, :amount, filter: expr(method == :stripe), default: Decimal.new("0")
  end
end

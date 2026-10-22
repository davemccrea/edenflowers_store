defmodule Edenflowers.Payments.Payable do
  @moduledoc """
  What's owed on an order or a course booking, worked out once from its
  `Payment` rows (ADR 0002), so both read the same.

  The including resource supplies:

    * an `:email_receipt` update action that emails the customer their receipt

    * `has_many :payments`
    * `calculate :total_due`: what it's still to be paid for, 0 once cancelled
      apart from anything kept when it was cancelled.
    * `calculate :committed?`: whether money is owed on it at all, so not an
      unplaced cart or a booking still holding its seats while the customer pays.
    * `calculate :cancelled?`
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Edenflowers.Payments.Changes
  alias Edenflowers.Payments.Validations

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

    # Money Jennie took or handed back by any method except Stripe.
    update :record_payment do
      argument :amount, :decimal, allow_nil?: false, constraints: [scale: 2]
      argument :payment_method, Edenflowers.Payments.PaymentMethod, allow_nil?: false
      argument :email_receipt?, :boolean, default: false

      validate argument_does_not_equal(:payment_method, :stripe), message: "is recorded from Stripe"
      validate Validations.Recordable
      # A payment link charges the balance this changes; visiting it again
      # opens a PaymentIntent for whatever is left.
      change Changes.CancelOpenPaymentIntent
      change {Changes.RecordPayment, amount: :amount}
      change Changes.EmailReceipt, where: [argument_equals(:email_receipt?, true)]
      require_atomic? false
    end

    # Money handed back to an unhappy customer by any method except Stripe,
    # without lowering what was sold. Payments.refund_goodwill/3 does it
    # through Stripe.
    update :goodwill_refund do
      argument :amount, :decimal, allow_nil?: false, constraints: [greater_than: 0, scale: 2]
      argument :payment_method, Edenflowers.Payments.PaymentMethod, allow_nil?: false
      argument :note, :string
      argument :refund, :decimal, public?: false

      validate argument_does_not_equal(:payment_method, :stripe), message: "is refunded with Stripe"
      validate Validations.GoodwillRefundable

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :amount) do
          %Decimal{} = amount -> Ash.Changeset.set_argument(changeset, :refund, Decimal.negate(amount))
          _invalid -> changeset
        end
      end

      change {Changes.RecordPayment, amount: :refund, goodwill: true}
      require_atomic? false
    end

    # Takes back a payment Jennie recorded by mistake, once, by recording the
    # opposite amount against it. A refund on something that still stands
    # otherwise has to wait until it's lowered (Validations.Recordable), or be
    # a goodwill refund.
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
                  balance >= 0 or paid_through_stripe <= 0 -> 0
                  -balance < paid_through_stripe -> -balance
                  true -> paid_through_stripe
                end
              )

    # Whether Jennie can hand money back without lowering what was sold
    # (Validations.GoodwillRefundable).
    calculate :goodwill_refundable?,
              :boolean,
              expr(committed? and not cancelled? and balance <= 0 and amount_held > 0)
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

defmodule Edenflowers.Payments.Payable do
  @moduledoc """
  What's owed on an order or a course booking, worked out once from its
  `Payment` rows (ADR 0002), so both read the same.

  The including resource supplies:

    * a `:by_payment_link_token` read action loading `payment_link_open?`
      and `balance`, and a policy letting anyone run `:prepare_link_payment`:
      the token is the access

    * a `:send_payment_received_email` update action, taking `amount` and
      `message`, that emails the customer Payment received

    * `has_many :payments`
    * `calculate :total_due`: what it's still to be paid for. Once cancelled,
      that's `kept_amount`.
    * `calculate :committed?`: whether money is owed on it at all, so not an
      unplaced cart or a website course checkout still waiting for its payment.
    * `calculate :cancelled?`
    * `calculate :cancellable?`: whether it can be cancelled now
    * `calculate :refund_on_cancelling`: what cancelling it now refunds unless
      Jennie says otherwise. An order refunds all it holds; a booking applies
      its course's cancellation terms.
    * `customer_email`: who's told about cancels and refunds, or nil
    * a `:for_customer_email` read action that loads what `Email.cancelled/2`
      and `Email.refunded/2` need
    * `cancelled_at` and `cancellation_emailed_to` attributes, and a `:cancel`
      update action with `Changes.Cancel` and its `refund`, `held` and
      `email_customer?` arguments
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Edenflowers.Payments.Calculations
  alias Edenflowers.Payments.Changes
  alias Edenflowers.Payments.Validations

  attributes do
    attribute :kept_amount, :decimal do
      description "Money in euros not handed back when it was cancelled: what Jennie chose to keep. " <>
                    "0 until cancelled."

      allow_nil? false
      default 0
      constraints min: 0, scale: 2
    end
  end

  actions do
    action :prepare_link_payment, :map do
      description "Readies the PaymentIntent behind a Payment Link for what is owed now and returns its client " <>
                    "secret. The token is the only access; refuses a closed link or a Balance that changed " <>
                    "from what the customer saw."

      argument :token, :string, allow_nil?: false, sensitive?: true
      argument :shown_balance, :decimal, allow_nil?: false, constraints: [greater_than: 0]
      run Edenflowers.Payments.Actions.PrepareLinkPayment
    end

    update :add_payment_intent_id do
      description "Stores the PaymentIntent just created for paying what is owed. Refuses one already set, or " <>
                    "nothing payable. Set by the system actor that creates the PaymentIntent."

      accept [:payment_intent_id]
      validate Validations.PaymentIntentNotSet
      validate Validations.Payable
    end

    update :mark_payment_cancelled do
      description "Forgets a PaymentIntent cancelled in Stripe, so the next payment creates a fresh one. " <>
                    "Refuses one the record no longer holds."

      argument :payment_intent_id, :string, allow_nil?: false
      validate Validations.MatchesPaymentIntent
      change set_attribute(:payment_intent_id, nil)
    end

    # Each resource triggers it with its own `where`.
    update :reconcile_payment do
      description "Rechecks an open PaymentIntent with Stripe and completes a payment whose webhook never " <>
                    "arrived, so a paid record isn't left pending. Run by Oban every 10 minutes."

      accept []
      transaction? false
      require_atomic? false
      change Changes.Reconcile
    end

    update :record_payment do
      description "Records money Jennie took by any method except Stripe, optionally emailing the customer a receipt."

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

    update :refund do
      description "Money Jennie hands back, by any method, with or without cancelling: through Stripe at once, or " <>
                    "recorded as handed back. What was owed back is an ordinary refund and the rest a Goodwill " <>
                    "refund, so the record stays settled either way."

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

    update :undo_payment do
      description "Takes back a payment or refund Jennie recorded by mistake by recording the opposite amount. " <>
                    "Once per payment, never a Stripe one."

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

    # `goodwill` says what a refund made here was; for one made in the
    # dashboard, the part beyond what was owed back is goodwill, recorded as
    # its own payment.
    update :record_stripe_refund do
      description "Records a Stripe refund from its webhook, so one Jennie makes in the Stripe dashboard shows up " <>
                    "without her entering it again. Recorded whatever it is, because the money moved."

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
    calculate :balance,
              :decimal,
              expr(
                cond do
                  total_due >= amount_paid -> total_due - amount_paid
                  total_due >= amount_held -> 0
                  true -> total_due - amount_held
                end
              ) do
      description "The Balance in euros: positive is still to collect, negative is to refund. A Goodwill refund " <>
                    "leaves it alone while the price stands, but once it drops below what was paid, only money " <>
                    "still held above it is owed back."
    end

    calculate :refunded?,
              :boolean,
              expr(
                exists(payments, amount > 0 and is_nil(reverses_payment_id) and not exists(reversal, true)) and
                  amount_held <= 0
              ) do
      description "Whether money was taken and all of it handed back. An undone payment and its undo don't " <>
                    "count as taking and handing back money."
    end

    calculate :payable?, :boolean, expr(balance > 0 and not refunded?) do
      description "Whether there is something a PaymentIntent can charge: a Balance to collect, and not refunded."
    end

    calculate :settled?, :boolean, expr(balance == 0 or refunded?) do
      description "Whether it is Settled. One refunded in Stripe without being cancelled reads as owed again by " <>
                    "its Balance, but is settled."
    end

    calculate :to_collect?, :boolean, expr(not settled? and balance > 0) do
      description "Whether money is still owed by the customer."
    end

    calculate :to_refund?, :boolean, expr(not settled? and balance < 0) do
      description "Whether money is owed back to the customer."
    end

    calculate :refundable?, :boolean, expr(committed? and balance <= 0 and amount_held > 0) do
      description "Whether Jennie can hand money back now: committed, nothing left to collect and money still " <>
                    "held. Validations.Refundable applies the same rules."
    end

    calculate :refund_methods, {:array, Edenflowers.Payments.PaymentMethod}, Calculations.RefundMethods do
      description "The methods Jennie can hand money back by: Stripe while money paid through it is held, and " <>
                    "any other method while money paid outside it is. Empty when nothing is held."
    end

    calculate :default_refund_method, Edenflowers.Payments.PaymentMethod, Calculations.DefaultRefundMethod do
      description "The refund method the admin form starts at: Stripe when possible, else the method holding " <>
                    "the most money paid outside Stripe. Nil when nothing can be refunded."
    end
  end

  aggregates do
    sum :amount_paid, :payments, :amount do
      description "What the customer paid in euros for what was sold: net of ordinary refunds, leaving out " <>
                    "Goodwill refunds."

      filter expr(not goodwill)
      default Decimal.new("0")
    end

    sum :amount_held, :payments, :amount do
      description "The money in euros still with the shop: every payment and refund, Goodwill refunds included."
      default Decimal.new("0")
    end

    sum :paid_outside_stripe, :payments, :amount do
      description "Money in euros held from methods other than Stripe, after refunds made the same way."
      filter expr(method != :stripe)
      default Decimal.new("0")
    end

    sum :paid_through_stripe, :payments, :amount do
      description "Money in euros held from Stripe payments, after Stripe refunds."
      filter expr(method == :stripe)
      default Decimal.new("0")
    end
  end
end

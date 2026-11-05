defmodule Edenflowers.Payments.Payable do
  @moduledoc """
  What's owed on an order or a course booking, worked out once from its
  `Payment` rows (ADR 0002), so both read the same.

  The including resource supplies:

    * a `:by_payment_link_token` read action loading `payment_link_open?`
      and `balance`, and a policy letting anyone run `:prepare_link_payment`:
      the token is the access

    * a `:send_payment_received_email` update action, taking `amount` and
      `subject` and `body`, that emails the customer Payment received

    * `has_many :payments`
    * `calculate :total_due`: what it's still to be paid for. Once cancelled,
      that's `kept_amount`, the cancellation charge.
    * `amount_invoiced`: what its issued, uncredited invoices bill, which
      the Balance leaves to them. A course booking is never invoiced: 0.
    * `calculate :committed?`: whether money is owed on it at all, so not an
      unplaced cart or a website course checkout still waiting for its payment.
    * `calculate :cancelled?`
    * `calculate :saves_card?`: whether paying it saves the card for later
      charges, so a Gift voucher must leave Stripe something to charge
    * `calculate :cancellable?`: whether it can be cancelled now
    * `calculate :default_cancellation_charge`: what cancelling it now keeps
      unless Jennie enters a charge. An order keeps nothing; a booking applies
      its course's cancellation terms.
    * `customer_email`: who's told about cancels and refunds, or nil
    * a `:for_customer_email` read action that loads what `Email.cancelled/2`
      and `Email.refunded/2` need
    * `cancelled_at` and `cancellation_emailed_to` attributes, and a `:cancel`
      update action with `Changes.Cancel` and its `cancellation_charge` and
      `email_customer?` arguments
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Edenflowers.Payments.Calculations
  alias Edenflowers.Payments.Changes
  alias Edenflowers.Payments.Validations

  attributes do
    attribute :kept_amount, :decimal do
      description "The cancellation charge in euros Jennie kept when it was cancelled, paid or not, which " <>
                    "becomes its Total due. 0 until cancelled."

      allow_nil? false
      default 0
      constraints min: 0, scale: 2
    end
  end

  relationships do
    belongs_to :gift_voucher, Edenflowers.Payments.GiftVoucher do
      description "The Gift voucher the customer entered at checkout. It pays when the purchase is placed or " <>
                    "confirmed; until then it only lowers what Stripe is asked to charge."
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
      description "Records money Jennie took by any method except Stripe, optionally emailing the customer a receipt. " <>
                    "Payments belong directly to this purchase."

      argument :amount, Edenflowers.Types.Price, allow_nil?: false, constraints: [greater_than: 0, scale: 2]
      argument :payment_method, Edenflowers.Payments.PaymentMethod, allow_nil?: false
      argument :email_receipt?, :boolean, default: false

      argument :subject, :string,
        description: "Jennie's own subject for the email, in place of the template's, if she rewrote it."

      argument :body, :string,
        description: "Jennie's own text for the email, in place of the template's, if she rewrote it."

      validate argument_does_not_equal(:payment_method, :stripe), message: "is recorded from Stripe"
      validate argument_does_not_equal(:payment_method, :voucher), message: "is paid from a Gift voucher's code"
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

      argument :amount, Edenflowers.Types.Price, allow_nil?: false, constraints: [greater_than: 0, scale: 2]
      argument :payment_method, Edenflowers.Payments.PaymentMethod, allow_nil?: false
      argument :note, :string, description: "Jennie's note on the refund, for her own records and Stripe's."
      argument :email_customer?, :boolean, default: true

      argument :subject, :string,
        description: "Jennie's own subject for the email, in place of the template's, if she rewrote it."

      argument :body, :string,
        description: "Jennie's own text for the email, in place of the template's, if she rewrote it."

      argument :refund, :decimal, public?: false
      argument :owed_back, :decimal, public?: false
      argument :goodwill_refund, :decimal, public?: false
      argument :gift_voucher_id, :uuid, public?: false

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
                  total_due - amount_invoiced >= amount_paid -> total_due - amount_invoiced - amount_paid
                  total_due - amount_invoiced >= amount_held -> 0
                  true -> total_due - amount_invoiced - amount_held
                end
              ) do
      description "The Balance in euros: what is left to collect here, positive, or to refund, negative. What " <>
                    "its invoices bill is theirs to collect, so an invoiced order reads 0 before it is paid. A " <>
                    "Goodwill refund leaves it alone while the price stands, but once it drops below what was " <>
                    "paid, only money still held above it is owed back."
    end

    # Stripe refuses to charge less than 0.50 €, so a voucher that nearly
    # covers a purchase leaves that much for the card. So does one that covers
    # a purchase saving the card: Stripe only saves it with a charge.
    calculate :voucher_amount,
              :decimal,
              expr(
                cond do
                  is_nil(gift_voucher_id) or not gift_voucher.spendable? -> 0
                  gift_voucher.remaining >= total_due and not saves_card? -> total_due
                  total_due - gift_voucher.remaining >= ^Decimal.new("0.50") -> gift_voucher.remaining
                  total_due > ^Decimal.new("0.50") -> total_due - ^Decimal.new("0.50")
                  true -> 0
                end
              ) do
      description "At checkout, what the Gift voucher entered will pay in euros: all of the Total due if what's " <>
                    "left covers it, else what's left, short of Stripe's 0.50 € minimum for the card, which a " <>
                    "purchase saving the card always pays. 0 with no voucher, or one expired or used up."
    end

    calculate :voucher_left_after, :decimal, expr(gift_voucher.remaining - voucher_amount) do
      description "At checkout, what will be left on the Gift voucher entered once it has paid for this, in " <>
                    "euros. Nil with no voucher."
    end

    calculate :stripe_amount, :decimal, expr(total_due - voucher_amount) do
      description "At checkout, what Stripe is asked to charge in euros: the Total due less what the Gift voucher " <>
                    "pays. 0 when the voucher covers it all, and it's placed without Stripe."
    end

    calculate :card_needed?, :boolean, expr(stripe_amount > 0) do
      description "At checkout, whether Stripe has anything to charge. False when the Gift voucher entered pays " <>
                    "it all, so it's placed or confirmed without the card form."
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
      description "The methods Jennie can hand money back by: Stripe while money paid through it is held, the " <>
                    "Gift voucher while money it paid is, and any other method while money paid in person is. " <>
                    "Empty when nothing is held."
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
      description "Money in euros held from what Jennie took in person, after refunds made the same way: not " <>
                    "Stripe, and not a Gift voucher, whose money only ever goes back onto the voucher."

      filter expr(method not in [:stripe, :voucher])
      default Decimal.new("0")
    end

    sum :paid_by_voucher, :payments, :amount do
      description "Money in euros held from Gift vouchers, after what was handed back onto them."
      filter expr(method == :voucher)
      default Decimal.new("0")
    end

    sum :paid_through_stripe, :payments, :amount do
      description "Money in euros held from Stripe payments, after Stripe refunds."
      filter expr(method == :stripe)
      default Decimal.new("0")
    end
  end
end

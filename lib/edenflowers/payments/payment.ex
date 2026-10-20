defmodule Edenflowers.Payments.Payment do
  @moduledoc """
  Money that moved for an order or a course booking: paid through Stripe
  (checkout or a payment link), recorded by Jennie, or handed back. A refund is
  a negative payment. It belongs to exactly one order or one registration.

  Only money that actually moved is recorded. A PaymentIntent still waiting
  for the customer lives on the order or registration as `payment_intent_id`
  until it succeeds. The unique Stripe ids are what make a redelivered webhook
  harmless: the same PaymentIntent or refund can't be recorded twice.

  `payment_method_type` says what paid, for the receipt: Stripe's payment
  method type ("card", "mobilepay", …) with the card's brand and last four, or
  the method Jennie recorded. It's blank on payments recorded before it existed, so
  their receipts stay as they were sent.

  A `goodwill` refund hands money back without lowering what was sold, so it
  leaves the balance alone. Jennie can give it a `note` saying why.
  """
  use Ash.Resource,
    domain: Edenflowers.Payments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Customers pay after delivery, on the usual Finnish invoice term; what's
  # still owed this long after an order is fulfilled or a course held is overdue.
  @overdue_after_days 14

  def overdue_after_days, do: @overdue_after_days

  postgres do
    repo Edenflowers.Repo
    table "payments"
    migration_types amount: :decimal

    check_constraints do
      check_constraint :amount, "payments_valid_amount",
        check: "amount = round(amount, 2)",
        message: "must be an amount in whole cents"

      check_constraint :order_id, "payments_one_parent",
        check: "(order_id IS NULL) <> (course_registration_id IS NULL)",
        message: "must belong to exactly one order or course registration"
    end

    references do
      reference :order, on_delete: :delete
      reference :course_registration, on_delete: :delete
      reference :reverses_payment, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    # Created by the order and registration actions that take or return
    # money, never on its own.
    create :record do
      accept [
        :order_id,
        :course_registration_id,
        :amount,
        :method,
        :payment_intent_id,
        :stripe_refund_id,
        :payment_method_type,
        :card_brand,
        :card_last4,
        :reverses_payment_id,
        :goodwill,
        :note
      ]
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action_type(:read)
    end

    policy action_type(:read) do
      authorize_if expr(order.user_id == ^actor(:id))
      authorize_if expr(course_registration.user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :amount, :decimal, allow_nil?: false, constraints: [scale: 2]
    attribute :method, Edenflowers.Payments.PaymentMethod, allow_nil?: false
    attribute :payment_intent_id, :string
    attribute :stripe_refund_id, :string
    attribute :payment_method_type, :string
    attribute :card_brand, :string
    attribute :card_last4, :string
    attribute :goodwill, :boolean, allow_nil?: false, default: false
    attribute :note, :string
    attribute :paid_at, :utc_datetime, allow_nil?: false, default: &DateTime.utc_now/0
    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Orders.Order
    belongs_to :course_registration, Edenflowers.Courses.CourseRegistration

    # An undo is the opposite amount, pointing at the payment it takes back.
    belongs_to :reverses_payment, __MODULE__
    has_one :reversal, __MODULE__, destination_attribute: :reverses_payment_id
  end

  calculations do
    calculate :undoable?,
              :boolean,
              expr(method != :stripe and is_nil(reverses_payment_id) and not exists(reversal, true))
  end

  identities do
    identity :unique_payment_intent, [:payment_intent_id]
    # A Stripe refund beyond what was owed back is split off as goodwill.
    identity :unique_stripe_refund, [:stripe_refund_id, :goodwill]
    identity :unique_reversal, [:reverses_payment_id]
  end
end

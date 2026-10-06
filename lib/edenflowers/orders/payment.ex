defmodule Edenflowers.Orders.Payment do
  @moduledoc """
  Money that moved for an order: paid through Stripe (checkout or a payment
  link), taken in person, or handed back. A refund is a negative payment.

  Only money that actually moved is recorded. A PaymentIntent still waiting
  for the customer lives on the order as `payment_intent_id` until it
  succeeds. The unique Stripe ids are what make a redelivered webhook
  harmless: the same PaymentIntent or refund can't be recorded twice.
  """
  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo Edenflowers.Repo
    table "payments"
    migration_types amount: :decimal

    check_constraints do
      check_constraint :amount, "payments_valid_amount",
        check: "amount = round(amount, 2)",
        message: "must be an amount in whole cents"
    end

    references do
      reference :order, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    # Created by the order actions that take or return money, never on its own.
    create :record do
      accept [:order_id, :amount, :method, :payment_intent_id, :stripe_refund_id]
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if action_type(:read)
    end

    policy action_type(:read) do
      authorize_if expr(order.user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :amount, :decimal, allow_nil?: false, constraints: [scale: 2]
    attribute :method, Edenflowers.Orders.Order.PaymentMethod, allow_nil?: false
    attribute :payment_intent_id, :string
    attribute :stripe_refund_id, :string
    attribute :paid_at, :utc_datetime, allow_nil?: false, default: &DateTime.utc_now/0
    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Orders.Order, allow_nil?: false
  end

  identities do
    identity :unique_payment_intent, [:payment_intent_id]
    identity :unique_stripe_refund, [:stripe_refund_id]
  end
end

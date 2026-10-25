defmodule Edenflowers.Orders.Order.Customer do
  @moduledoc """
  What a Customer does with their own placed orders from their account.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource

  import Ash.Expr, only: [expr: 1]

  alias Edenflowers.Orders.Changes.NotifyShop
  alias Edenflowers.Orders.Order.Changes
  alias Edenflowers.Orders.Order.Validations
  alias Edenflowers.Payments.Changes, as: PaymentChanges

  actions do
    # Scoped to the actor by filter, not by policy: the admin bypass in policies grants
    # admins an unrestricted read, so an action named for the customer's own
    # order history has to narrow itself or it hands Jennie everyone's orders.
    read :mine do
      description "The actor's own placed orders, newest first, with what their order history shows. " <>
                    "Filtered to the actor even for an admin."

      filter expr(state == :placed and user_id == ^actor(:id))

      prepare build(
                sort: [ordered_at: :desc, inserted_at: :desc],
                load: [
                  :payment_status,
                  :unpaid?,
                  :grand_total,
                  :payment_link_open?,
                  :amount_paid,
                  :cancellable_by_customer?,
                  :cancellable_until,
                  :customer_status,
                  :upcoming?,
                  :receipt_available?
                ]
              )
    end

    update :cancel_by_customer do
      description "A customer cancelling their own Online Order from their account, before the Change deadline and " <>
                    "only when paid by card: refunds it all through Stripe, puts stock back and notifies the shop."

      validate Validations.CancellableByCustomer
      change set_attribute(:fulfillment_status, :cancelled)
      change {PaymentChanges.Cancel, cancelled_by: :customer}
      change {Changes.AdjustStock, direction: :return}
      change {NotifyShop, notice: :cancelled}
      require_atomic? false
    end
  end
end

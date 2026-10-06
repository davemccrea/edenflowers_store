defmodule Edenflowers.Orders.Changes.RecordPayment do
  @moduledoc """
  Records the money an order action took or handed back as a `Payment`.

  Options:

    * `:amount` - the argument holding the amount.
    * `:method` - the payment method; read from the `:payment_method`
      argument when not given.

  Stripe ids come from the `:payment_intent_id` and `:stripe_refund_id`
  arguments, where the action has them.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.Payment

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      Payment
      |> Ash.Changeset.for_create(:record, %{
        order_id: order.id,
        amount: Ash.Changeset.get_argument(changeset, opts[:amount]),
        method: opts[:method] || Ash.Changeset.get_argument(changeset, :payment_method),
        payment_intent_id: Map.get(changeset.arguments, :payment_intent_id),
        stripe_refund_id: Map.get(changeset.arguments, :stripe_refund_id)
      })
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _payment} -> {:ok, order}
        error -> error
      end
    end)
  end
end

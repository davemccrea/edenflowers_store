defmodule Edenflowers.Orders.Changes.RecordPayment do
  @moduledoc """
  Records the money an order action took or handed back as a `Payment`.

  Options:

    * `:amount` - the argument holding the amount.
    * `:method` - the payment method; read from the `:payment_method`
      argument when not given.

  Stripe ids come from the `:payment_intent_id` and `:stripe_refund_id`
  arguments, where the action has them, and a Stripe payment's method from
  the `:paid_with` argument (see `Edenflowers.Payments.paid_with/1`).
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.Payment

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      method = opts[:method] || Ash.Changeset.get_argument(changeset, :payment_method)

      Payment
      |> Ash.Changeset.for_create(
        :record,
        Map.merge(paid_with(changeset, method), %{
          order_id: order.id,
          amount: Ash.Changeset.get_argument(changeset, opts[:amount]),
          method: method,
          payment_intent_id: Map.get(changeset.arguments, :payment_intent_id),
          stripe_refund_id: Map.get(changeset.arguments, :stripe_refund_id)
        })
      )
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _payment} -> Ash.load(order, :payment_status, authorize?: false, reuse_values?: false)
        error -> error
      end
    end)
  end

  # A refund isn't something the customer paid with.
  defp paid_with(changeset, :stripe) do
    if Map.has_key?(changeset.arguments, :stripe_refund_id),
      do: %{},
      else: Map.get(changeset.arguments, :paid_with, %{})
  end

  defp paid_with(_changeset, in_person), do: %{payment_method_type: to_string(in_person)}
end

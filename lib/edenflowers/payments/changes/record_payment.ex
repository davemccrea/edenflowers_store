defmodule Edenflowers.Payments.Changes.RecordPayment do
  @moduledoc """
  Records the money an order or course registration action took or handed
  back as a `Payment`.

  Options:

    * `:amount` - the argument holding the amount.
    * `:method` - the payment method; read from the `:payment_method`
      argument when not given.

  Stripe ids come from the `:payment_intent_id` and `:stripe_refund_id`
  arguments, and the payment an undo takes back from `:reverses_payment_id`,
  where the action has them, and a Stripe payment's method from
  the `:paid_with` argument (see `Edenflowers.Payments.paid_with/1`).
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.Payment

  # Whatever the caller loaded about the money is stale now.
  @payable_fields [:amount_paid, :paid_outside_stripe, :balance, :refunded?, :settled?]

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, record ->
      method = opts[:method] || Ash.Changeset.get_argument(changeset, :payment_method)

      Payment
      |> Ash.Changeset.for_create(
        :record,
        Map.merge(paid_with(changeset, method), %{
          Edenflowers.Payments.parent_key(record) => record.id,
          amount: Ash.Changeset.get_argument(changeset, opts[:amount]),
          method: method,
          payment_intent_id: Map.get(changeset.arguments, :payment_intent_id),
          stripe_refund_id: Map.get(changeset.arguments, :stripe_refund_id),
          reverses_payment_id: Map.get(changeset.arguments, :reverses_payment_id)
        })
      )
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _payment} -> reload(record)
        error -> error
      end
    end)
  end

  defp reload(%Order{} = order),
    do: Ash.load(order, [:payment_status | @payable_fields], authorize?: false, reuse_values?: false)

  defp reload(registration), do: Ash.load(registration, @payable_fields, authorize?: false, reuse_values?: false)

  # A refund isn't something the customer paid with.
  defp paid_with(changeset, :stripe) do
    if Map.has_key?(changeset.arguments, :stripe_refund_id),
      do: %{},
      else: Map.get(changeset.arguments, :paid_with, %{})
  end

  defp paid_with(_changeset, method), do: %{payment_method_type: to_string(method)}
end

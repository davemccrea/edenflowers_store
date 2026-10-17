defmodule Edenflowers.Payments.Changes.RecordPayment do
  @moduledoc """
  Records the money an order or course registration action took or handed
  back as a `Payment`.

  Options:

    * `:amount` - the argument holding the amount.
    * `:method` - the payment method; read from the `:payment_method`
      argument when not given.

  Stripe ids come from the `:payment_intent_id` and `:stripe_refund_id`
  arguments, where the action has them, and a Stripe payment's method from
  the `:paid_with` argument (see `Edenflowers.Payments.paid_with/1`).
  """
  use Ash.Resource.Change

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.Payment

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, record ->
      method = opts[:method] || Ash.Changeset.get_argument(changeset, :payment_method)

      Payment
      |> Ash.Changeset.for_create(
        :record,
        Map.merge(paid_with(changeset, method), %{
          parent_key(record) => record.id,
          amount: Ash.Changeset.get_argument(changeset, opts[:amount]),
          method: method,
          payment_intent_id: Map.get(changeset.arguments, :payment_intent_id),
          stripe_refund_id: Map.get(changeset.arguments, :stripe_refund_id)
        })
      )
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _payment} -> reload(record)
        error -> error
      end
    end)
  end

  defp parent_key(%Order{}), do: :order_id
  defp parent_key(%CourseRegistration{}), do: :course_registration_id

  defp reload(%Order{} = order), do: Ash.load(order, :payment_status, authorize?: false, reuse_values?: false)
  defp reload(registration), do: {:ok, registration}

  # A refund isn't something the customer paid with.
  defp paid_with(changeset, :stripe) do
    if Map.has_key?(changeset.arguments, :stripe_refund_id),
      do: %{},
      else: Map.get(changeset.arguments, :paid_with, %{})
  end

  defp paid_with(_changeset, method), do: %{payment_method_type: to_string(method)}
end

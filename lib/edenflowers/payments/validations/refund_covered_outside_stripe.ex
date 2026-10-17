defmodule Edenflowers.Payments.Validations.RefundCoveredOutsideStripe do
  @moduledoc """
  Refuses a refund Jennie records that is larger than the money paid outside
  Stripe, read from the record's `paid_outside_stripe` aggregate. Money paid
  through Stripe is refunded through Stripe.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    amount = Ash.Changeset.get_argument(changeset, :amount)

    if is_struct(amount, Decimal) and Decimal.negative?(amount) and
         Decimal.negative?(Decimal.add(paid_outside_stripe(changeset.data), amount)) do
      {:error, field: :amount, message: "is more than was paid outside Stripe"}
    else
      :ok
    end
  end

  defp paid_outside_stripe(record) do
    record
    |> Ash.load!(:paid_outside_stripe, authorize?: false, reuse_values?: false)
    |> Map.fetch!(:paid_outside_stripe)
  end
end

defmodule Edenflowers.Payments.Validations.InPersonRefundCovered do
  @moduledoc """
  Refuses an in-person refund larger than the money taken in person, read
  from the record's `in_person_paid` aggregate. Money paid through Stripe is
  refunded through Stripe.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    amount = Ash.Changeset.get_argument(changeset, :amount)

    if is_struct(amount, Decimal) and Decimal.negative?(amount) and
         Decimal.negative?(Decimal.add(in_person_paid(changeset.data), amount)) do
      {:error, field: :amount, message: "is more than was paid in person"}
    else
      :ok
    end
  end

  defp in_person_paid(record) do
    record
    |> Ash.load!(:in_person_paid, authorize?: false, reuse_values?: false)
    |> Map.fetch!(:in_person_paid)
  end
end

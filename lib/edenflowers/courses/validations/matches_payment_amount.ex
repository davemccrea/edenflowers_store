defmodule Edenflowers.Courses.Validations.MatchesPaymentAmount do
  use Ash.Resource.Validation

  alias Edenflowers.Payments.Errors.AmountMismatch

  @impl true
  def atomic(changeset, _opts, _context) do
    amount_paid = Ash.Changeset.get_argument(changeset, :amount_paid)

    # A nil argument is already rejected by allow_nil? false.
    if is_nil(amount_paid) do
      :ok
    else
      {:atomic, :*, expr(amount != ^amount_paid),
       expr(error(^AmountMismatch, %{expected: amount, actual: ^amount_paid}))}
    end
  end
end

defmodule Edenflowers.Courses.Changes.SetRefund do
  @moduledoc """
  Leaves `amount` as the balance to refund by keeping the rest of what's owed
  back, or giving back what was kept.
  """

  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def change(%{valid?: false} = changeset, _opts, _context), do: changeset

  def change(changeset, _opts, _context) do
    amount = Ash.Changeset.get_argument(changeset, :amount)
    registration = Ash.load!(changeset.data, [:balance], authorize?: false, reuse_values?: false)
    kept = registration.kept_amount |> Decimal.sub(registration.balance) |> Decimal.sub(amount)

    if Decimal.negative?(kept),
      do: Ash.Changeset.add_error(changeset, field: :amount, message: ~t"That's more than is owed back."),
      else: Ash.Changeset.force_change_attribute(changeset, :kept_amount, kept)
  end
end

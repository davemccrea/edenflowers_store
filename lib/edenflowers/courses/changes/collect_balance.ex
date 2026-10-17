defmodule Edenflowers.Courses.Changes.CollectBalance do
  @moduledoc """
  Sets the private `:amount` argument to the booking's positive balance, so
  the payment recorded is exactly what is owed. Refused when nothing is owed.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    %{balance: balance} = Ash.load!(changeset.data, :balance, authorize?: false, reuse_values?: false)

    if Decimal.positive?(balance),
      do: Ash.Changeset.set_argument(changeset, :amount, balance),
      else: Ash.Changeset.add_error(changeset, field: :balance, message: "nothing is owed")
  end
end

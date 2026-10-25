defmodule Edenflowers.Orders.Validations.Holds do
  @moduledoc """
  Refuses the action unless the order's boolean `calculation` is true, read
  fresh so a copy loaded before someone else's change can't pass. The same
  calculation tells the admin whether to offer the action at all.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    calculation = Keyword.fetch!(opts, :calculation)
    order = Ash.load!(changeset.data, calculation, authorize?: false, reuse_values?: false)

    if Map.fetch!(order, calculation), do: :ok, else: {:error, message: Keyword.fetch!(opts, :message)}
  end
end

defmodule Edenflowers.Payments.Validations.Committed do
  @moduledoc "Refuses recording money on an unplaced cart or a booking still holding its seats while the customer pays."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.load!(changeset.data, :committed?, authorize?: false, reuse_values?: false).committed?,
      do: :ok,
      else: {:error, field: :amount, message: "can't be recorded before it's placed or confirmed"}
  end
end

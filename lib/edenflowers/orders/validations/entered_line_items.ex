defmodule Edenflowers.Orders.Validations.EnteredLineItems do
  use Ash.Resource.Validation

  alias Edenflowers.Orders.EnteredLineItems

  @impl true
  def validate(changeset, _opts, _context) do
    case EnteredLineItems.parse(Ash.Changeset.get_argument(changeset, :line_items)) do
      {:ok, _lines} -> :ok
      {:error, message} -> {:error, field: :line_items, message: message}
    end
  end
end

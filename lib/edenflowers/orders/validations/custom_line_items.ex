defmodule Edenflowers.Orders.Validations.CustomLineItems do
  use Ash.Resource.Validation

  alias Edenflowers.Orders.CustomLineItems

  @impl true
  def validate(changeset, _opts, _context) do
    case CustomLineItems.parse(Ash.Changeset.get_argument(changeset, :line_items)) do
      {:ok, _lines} -> :ok
      {:error, message} -> {:error, field: :line_items, message: message}
    end
  end
end

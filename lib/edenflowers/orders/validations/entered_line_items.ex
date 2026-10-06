defmodule Edenflowers.Orders.Validations.EnteredLineItems do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Orders.EnteredLineItems

  @impl true
  def validate(changeset, _opts, _context) do
    case EnteredLineItems.parse(Ash.Changeset.get_argument(changeset, :line_items)) do
      {:ok, _lines} -> :ok
      {:error, nil, message} -> {:error, field: :line_items, message: message}
      {:error, number, message} -> {:error, field: :line_items, message: ~t"Item #{number}: #{message}"}
    end
  end
end

defmodule Edenflowers.Store.Order.EncodeOrderReference do
  use Ash.Resource.Calculation

  alias Edenflowers.Sqids

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case Map.get(record, :order_number) do
        nil -> nil
        order_number -> Sqids.encode!([order_number])
      end
    end)
  end
end

defmodule Edenflowers.Orders.Changes.ReplaceCustomLineItems do
  @moduledoc """
  Replaces a custom order's lines with the ones in the `line_items` argument
  (see `Edenflowers.Orders.CustomLineItems`), then snapshots its VAT
  breakdown. Replacing rather than diffing keeps an edit the same as placing
  the order afresh; the lines carry no history worth keeping.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders
  alias Edenflowers.Orders.{CustomLineItems, LineItem}
  alias Edenflowers.Pricing.TaxRate

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      {:ok, lines} = CustomLineItems.parse(Ash.Changeset.get_argument(changeset, :line_items))

      with :ok <- remove_existing_lines(order),
           :ok <- add_lines(order, lines) do
        Orders.refresh_vat_breakdown(order, authorize?: false)
      end
    end)
  end

  defp remove_existing_lines(order) do
    %{line_items: line_items} = Ash.load!(order, :line_items, authorize?: false)

    Enum.reduce_while(line_items, :ok, fn line_item, :ok ->
      case Ash.destroy(line_item, action: :remove_item, authorize?: false) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp add_lines(order, lines) do
    Enum.reduce_while(lines, :ok, fn line, :ok ->
      case add_line(order, line) do
        {:ok, _line_item} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp add_line(order, {:catalogue, variant_id, quantity}) do
    Orders.add_line_item(order.id, variant_id, quantity, authorize?: false)
  end

  defp add_line(order, {:custom, description, unit_price, tax_rate_id, quantity}) do
    with {:ok, tax_rate} <- Ash.get(TaxRate, tax_rate_id, authorize?: false) do
      LineItem
      |> Ash.Changeset.for_create(:add_custom_item, %{
        order_id: order.id,
        product_name: description,
        unit_price: unit_price,
        tax_rate: tax_rate.percentage,
        quantity: quantity
      })
      |> Ash.create(authorize?: false)
    end
  end
end

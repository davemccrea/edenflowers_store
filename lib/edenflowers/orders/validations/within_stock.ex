defmodule Edenflowers.Orders.Validations.WithinStock do
  @moduledoc """
  A customer can't put more of a tracked size in their cart than is in stock.

  Only carts are held to it: Jennie's Custom Orders and edits are never
  refused, and a subscription's bouquets are made fresh.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Ash.Query

  alias Edenflowers.Catalog
  alias Edenflowers.Orders.{LineItem, Order}

  @impl true
  def validate(changeset, _opts, _context) do
    variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)
    order_id = Ash.Changeset.get_attribute(changeset, :order_id)

    with true <- not is_nil(variant_id) and is_nil(Ash.Changeset.get_attribute(changeset, :interval_weeks)),
         {:ok, %{stock_quantity: stock}} when not is_nil(stock) <-
           Catalog.get_variant_by_id(variant_id, authorize?: false),
         {:ok, %{origin: :online, state: state}} when state != :placed <-
           Ash.get(Order, order_id, authorize?: false),
         true <- quantity_after(changeset) > stock do
      {:error, field: :quantity, message: message(stock)}
    else
      _ -> :ok
    end
  end

  @doc "A cart's lines that now ask for more than is in stock, as others bought it meanwhile."
  def lines_over_stock(order) do
    %{line_items: line_items} = Ash.load!(order, [line_items: :product_variant], authorize?: false)

    Enum.filter(line_items, fn line_item ->
      variant = line_item.product_variant

      is_nil(line_item.interval_weeks) && variant && variant.stock_quantity &&
        line_item.quantity > variant.stock_quantity
    end)
  end

  def message(0), do: ~t"Sold out"
  def message(stock), do: ~t"Only #{stock} left"

  # Adding to the cart merges into a line it already has for the size.
  defp quantity_after(%{action_type: :create} = changeset) do
    order_id = Ash.Changeset.get_attribute(changeset, :order_id)
    variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)

    in_cart =
      LineItem
      |> Ash.Query.filter(order_id == ^order_id and product_variant_id == ^variant_id)
      |> Ash.read_one!(authorize?: false)

    Ash.Changeset.get_attribute(changeset, :quantity) + ((in_cart && in_cart.quantity) || 0)
  end

  defp quantity_after(%{action_type: :update} = changeset), do: changeset.data.quantity + 1
end

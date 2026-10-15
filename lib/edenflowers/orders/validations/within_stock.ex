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
    interval_weeks = Ash.Changeset.get_attribute(changeset, :interval_weeks)
    order_id = Ash.Changeset.get_attribute(changeset, :order_id)

    if is_nil(variant_id) or not is_nil(interval_weeks) do
      :ok
    else
      validate_stock(changeset, variant_id, order_id)
    end
  end

  def message(0), do: ~t"Sold out"
  def message(stock), do: ~t"Only #{stock} left"

  defp validate_stock(changeset, variant_id, order_id) do
    with {:ok, %{stock_quantity: stock}} when not is_nil(stock) <-
           Catalog.get_variant_by_id(variant_id, authorize?: false),
         {:ok, %{origin: :online, state: state}} when state != :placed <-
           Ash.get(Order, order_id, authorize?: false),
         true <- quantity_after(changeset) > stock do
      {:error, field: :quantity, message: message(stock)}
    else
      _ -> :ok
    end
  end

  # Adding to the cart merges into a line it already has for the size.
  defp quantity_after(%{action: %{name: :add_to_cart}} = changeset) do
    order_id = Ash.Changeset.get_attribute(changeset, :order_id)
    variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)

    in_cart =
      LineItem
      |> Ash.Query.filter(order_id == ^order_id and product_variant_id == ^variant_id)
      |> Ash.read_one!(authorize?: false)

    Ash.Changeset.get_attribute(changeset, :quantity) + ((in_cart && in_cart.quantity) || 0)
  end

  defp quantity_after(%{action: %{name: :increment_quantity}} = changeset), do: changeset.data.quantity + 1
end

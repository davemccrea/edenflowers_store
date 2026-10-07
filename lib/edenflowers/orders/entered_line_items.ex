defmodule Edenflowers.Orders.EnteredLineItems do
  @moduledoc """
  Parses the lines Jennie enters when she places or edits an order. Each line
  is either a catalogue variant, priced from the catalogue, or one she
  describes and prices herself:

      %{"kind" => "catalogue", "product_variant_id" => id, "quantity" => "1"}
      %{"kind" => "catalogue", "id" => line_item_id, "quantity" => "2"}
      %{"kind" => "custom", "description" => "Funeral spray", "unit_price" => "85.00",
        "tax_rate_id" => id, "quantity" => "1"}

  A catalogue line with an `id` is one the order already has. It keeps the
  price it was sold at, which the catalogue may since have changed.

  Keys may be strings or atoms, since the form sends strings and tests write atoms.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext

  @type line ::
          {:catalogue, variant_id :: String.t() | nil, quantity :: pos_integer(), line_item_id :: String.t() | nil}
          | {:custom, description :: String.t(), unit_price :: Decimal.t(), tax_rate_id :: String.t(),
             quantity :: pos_integer()}

  @doc """
  The lines, or the first problem: with the 1-based number of the line it is
  on, or nil when there are no lines at all.
  """
  @spec parse(list(map()) | nil) :: {:ok, [line()]} | {:error, pos_integer() | nil, String.t()}
  def parse(nil), do: {:error, nil, ~t"Add at least one item"}
  def parse([]), do: {:error, nil, ~t"Add at least one item"}

  def parse(items) when is_list(items) do
    items
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {item, number}, {:ok, lines} ->
      case parse_line(item) do
        {:ok, line} -> {:cont, {:ok, [line | lines]}}
        {:error, message} -> {:halt, {:error, number, message}}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  defp parse_line(item) do
    case fetch(item, :kind) do
      "catalogue" -> parse_catalogue(item)
      "custom" -> parse_custom(item)
      _ -> {:error, ~t"choose a product or describe the item"}
    end
  end

  defp parse_catalogue(item) do
    with {:ok, quantity} <- quantity(item) do
      case required(item, :id, nil) do
        {:ok, line_item_id} -> {:ok, {:catalogue, nil, quantity, line_item_id}}
        {:error, _} -> parse_new_catalogue(item, quantity)
      end
    end
  end

  defp parse_new_catalogue(item, quantity) do
    with {:ok, variant_id} <- required(item, :product_variant_id, ~t"choose a product") do
      {:ok, {:catalogue, variant_id, quantity, nil}}
    end
  end

  defp parse_custom(item) do
    with {:ok, description} <- required(item, :description, ~t"describe the item"),
         {:ok, unit_price} <- unit_price(item),
         {:ok, tax_rate_id} <- required(item, :tax_rate_id, ~t"choose a VAT rate"),
         {:ok, quantity} <- quantity(item) do
      {:ok, {:custom, description, unit_price, tax_rate_id, quantity}}
    end
  end

  defp required(item, key, message) do
    case fetch(item, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, message}
          value -> {:ok, value}
        end

      _ ->
        {:error, message}
    end
  end

  defp quantity(item) do
    case fetch(item, :quantity) do
      quantity when is_integer(quantity) and quantity > 0 ->
        {:ok, quantity}

      quantity when is_binary(quantity) ->
        case Integer.parse(String.trim(quantity)) do
          {quantity, ""} when quantity > 0 -> {:ok, quantity}
          _ -> {:error, ~t"enter a quantity of at least 1"}
        end

      _ ->
        {:error, ~t"enter a quantity of at least 1"}
    end
  end

  # Prices are typed the Finnish way too, with a decimal comma.
  defp unit_price(item) do
    raw = item |> fetch(:unit_price) |> to_string() |> String.trim() |> String.replace(",", ".")

    case Decimal.parse(raw) do
      {price, ""} ->
        if Decimal.negative?(price) do
          {:error, ~t"enter a price of 0 or more"}
        else
          {:ok, Decimal.round(price, 2)}
        end

      _ ->
        {:error, ~t"enter a price"}
    end
  end

  defp fetch(item, key) when is_map(item), do: Map.get(item, Atom.to_string(key), Map.get(item, key))
  defp fetch(_item, _key), do: nil
end

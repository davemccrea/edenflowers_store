defmodule Edenflowers.Orders.Changes.ReplaceLineItems do
  @moduledoc """
  Makes the order's lines the ones in the `line_items` argument (see
  `Edenflowers.Orders.EnteredLineItems`), then snapshots its VAT breakdown.

  A catalogue line the order already has is kept and only its quantity
  changes, so it keeps the price it was sold at, and a card stays a card.
  Every other line is replaced: a line Jennie priced herself carries its
  price in the form anyway.

  When the lines differ from what the order had, the order log's version
  for this action records them as `items`.
  """
  use Ash.Resource.Change

  alias Edenflowers.Catalog
  alias Edenflowers.Orders
  alias Edenflowers.Orders.{EnteredLineItems, LineItem}
  alias Edenflowers.Pricing.TaxRate

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(&log_changed_items/1)
    |> Ash.Changeset.after_action(fn changeset, order ->
      {:ok, lines} = EnteredLineItems.parse(Ash.Changeset.get_argument(changeset, :line_items))
      kept = for {:catalogue, nil, quantity, id} <- lines, into: %{}, do: {id, quantity}

      with :ok <- update_existing_lines(order, kept),
           :ok <- add_lines(order, Enum.reject(lines, &kept?/1)),
           {:ok, order} <- Orders.refresh_vat_breakdown(order, authorize?: false) do
        Ash.load(order, :payment_status, authorize?: false, reuse_values?: false)
      end
    end)
  end

  # Compared by name, quantity and price; logged by quantity and name.
  defp log_changed_items(changeset) do
    {:ok, lines} = EnteredLineItems.parse(Ash.Changeset.get_argument(changeset, :line_items))
    existing = existing_lines(changeset)

    case map_ok(lines, &describe(&1, existing)) do
      {:ok, entered} ->
        before = Map.values(existing)

        if Enum.sort(entered) == Enum.sort(before) do
          Ash.Changeset.set_context(changeset, %{skip_version_when_unchanged?: true})
        else
          items = Enum.map_join(entered, ", ", fn {name, quantity, _price} -> "#{quantity} × #{name}" end)
          Ash.Changeset.set_context(changeset, %{paper_trail_metadata: %{items: items}})
        end

      :error ->
        Ash.Changeset.add_error(changeset, field: :line_items, message: "contains an item that is no longer available")
    end
  end

  defp existing_lines(%{action_type: :create}), do: %{}

  defp existing_lines(changeset) do
    changeset.data
    |> Ash.load!(:line_items, authorize?: false)
    |> Map.fetch!(:line_items)
    |> Map.new(&{&1.id, {&1.product_name, &1.quantity, &1.unit_price}})
  end

  defp describe({:catalogue, nil, quantity, id}, existing) do
    case Map.fetch(existing, id) do
      {:ok, {name, _quantity, price}} -> {:ok, {name, quantity, price}}
      :error -> :error
    end
  end

  defp describe({:catalogue, variant_id, quantity, nil}, _existing) do
    case Catalog.get_variant_by_id(variant_id, load: [:product], authorize?: false) do
      {:ok, variant} -> {:ok, {variant.product.name, quantity, variant.price}}
      _ -> :error
    end
  end

  defp describe({:custom, description, unit_price, _tax_rate_id, quantity}, _existing),
    do: {:ok, {description, quantity, unit_price}}

  defp kept?({:catalogue, nil, _quantity, _id}), do: true
  defp kept?(_line), do: false

  defp update_existing_lines(order, kept) do
    %{line_items: line_items} = Ash.load!(order, :line_items, authorize?: false)

    each_ok(line_items, fn line_item ->
      case Map.fetch(kept, line_item.id) do
        {:ok, quantity} -> Ash.update(line_item, %{quantity: quantity}, action: :set_quantity, authorize?: false)
        :error -> Ash.destroy(line_item, action: :remove_item, authorize?: false)
      end
    end)
  end

  defp add_lines(order, lines), do: each_ok(lines, &add_line(order, &1))

  defp add_line(order, {:catalogue, variant_id, quantity, nil}) do
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

  defp each_ok(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        {:ok, _record} -> {:cont, :ok}
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp map_ok(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end
  end
end

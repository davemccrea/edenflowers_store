defmodule Edenflowers.Orders.Order.Changes.RecordEnteredLineItems do
  @moduledoc """
  Records the lines Jennie entered in the `line_items` argument, which
  `manage_relationship` saves: in the order log's version for this action when
  they differ from what the order had. Returns the order with the VAT breakdown
  and grand total the lines stored once saved.
  """
  use Ash.Resource.Change

  alias Edenflowers.Catalog
  alias Edenflowers.Format
  alias Edenflowers.Types.Price

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(&log_changed_items/1)
    # LineItem's RefreshPlacedOrder stored them as each line saved; this order
    # struct predates that, and KeepInvoicedAmounts compares its vat_breakdown.
    |> Ash.Changeset.after_action(fn _changeset, order ->
      Ash.load(order, [:vat_breakdown, :stored_grand_total, :payment_status], authorize?: false, reuse_values?: false)
    end)
  end

  # Compared by name, quantity and price; logged by quantity and name.
  defp log_changed_items(changeset) do
    existing = existing_lines(changeset)
    entered = Enum.map(Ash.Changeset.get_argument(changeset, :line_items), &describe(&1, existing))

    cond do
      :unknown in entered ->
        Ash.Changeset.add_error(changeset, field: :line_items, message: "contains an item that is no longer available")

      Enum.sort(entered) == Enum.sort(Map.values(existing)) ->
        Ash.Changeset.set_context(changeset, %{skip_version_when_unchanged?: true})

      true ->
        items = Enum.map_join(entered, ", ", fn {name, quantity, _price} -> "#{quantity} × #{name}" end)
        Ash.Changeset.set_context(changeset, %{paper_trail_metadata: %{items: items}})
    end
  end

  defp existing_lines(%{action_type: :create}), do: %{}

  defp existing_lines(changeset) do
    changeset.data
    |> Ash.load!(:line_items, authorize?: false)
    |> Map.fetch!(:line_items)
    |> Map.new(&{&1.id, {Format.line_item_name(&1), &1.quantity, &1.unit_price}})
  end

  # The lines arrive as the form sent them, before LineItem casts them.
  defp describe(line, existing) do
    quantity = quantity(fetch(line, :quantity))
    colour = line |> fetch(:bow_colour) |> cast_colour()

    cond do
      id = fetch(line, :id) ->
        case Map.fetch(existing, id) do
          {:ok, {name, _quantity, price}} -> {name, quantity, price}
          :error -> :unknown
        end

      variant_id = fetch(line, :product_variant_id) ->
        case Catalog.get_variant_by_id(variant_id, load: [:product], authorize?: false) do
          {:ok, variant} ->
            name =
              Format.line_item_name(%{
                product_name: variant.product.name,
                variant_size: variant.size,
                bow_colour: colour
              })

            {name, quantity, variant.price}

          _ ->
            :unknown
        end

      true ->
        {fetch(line, :product_name), quantity, price(fetch(line, :unit_price))}
    end
  end

  defp cast_colour(colour) do
    case Ash.Type.cast_input(Edenflowers.Catalog.BowColour, colour) do
      {:ok, colour} -> colour
      # LineItem refuses the line, so the log never records it.
      _ -> nil
    end
  end

  defp quantity(quantity) when is_binary(quantity) do
    case Integer.parse(quantity) do
      {quantity, ""} -> quantity
      _ -> quantity
    end
  end

  defp quantity(quantity), do: quantity

  defp price(price) do
    case Ash.Type.cast_input(Price, price) do
      {:ok, price} -> price
      _ -> price
    end
  end

  # Keys are strings from the form and atoms from tests; a blank field is nil.
  defp fetch(line, key) do
    case Map.get(line, Atom.to_string(key), Map.get(line, key)) do
      "" -> nil
      value -> value
    end
  end
end

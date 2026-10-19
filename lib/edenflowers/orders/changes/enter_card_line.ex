defmodule Edenflowers.Orders.Changes.EnterCardLine do
  @moduledoc """
  Adds the card Jennie chose (`card_variant_id`) to the `line_items` argument
  as the order's card line, so `manage_relationship` saves it with the rest.
  The card the order already has is kept by id, so it keeps the price it was
  sold at. Any other card the order had is missing from the argument, so it is
  removed, as it is when the order isn't a gift.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    variant_id = Ash.Changeset.get_argument(changeset, :card_variant_id)

    if variant_id && Ash.Changeset.get_attribute(changeset, :gift) do
      lines = Ash.Changeset.get_argument(changeset, :line_items)
      Ash.Changeset.set_argument(changeset, :line_items, lines ++ [card_line(changeset, variant_id)])
    else
      changeset
    end
  end

  defp card_line(changeset, variant_id) do
    case existing_card(changeset) do
      %{id: id, product_variant_id: ^variant_id} -> %{"id" => id, "quantity" => 1}
      _ -> %{"kind" => "catalogue", "product_variant_id" => variant_id, "quantity" => 1, "is_card" => true}
    end
  end

  defp existing_card(%{action_type: :create}), do: nil

  defp existing_card(changeset) do
    changeset.data
    |> Ash.load!(:line_items, authorize?: false)
    |> Map.fetch!(:line_items)
    |> Enum.find(& &1.is_card)
  end
end

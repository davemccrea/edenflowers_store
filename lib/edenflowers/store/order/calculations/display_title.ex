defmodule Edenflowers.Store.Order.Calculations.DisplayTitle do
  @moduledoc """
  Human-readable name for an Order, derived from its Line Items.

  Rule:

    * Excludes Line Items where `is_card == true` (the optional gift card is
      not what the Customer thinks of as "the order").
    * Of the remaining items, takes the one with the earliest `inserted_at`
      for sort stability.
    * If at least one non-card item exists: returns its `product_name`,
      appending `" + N more"` when more than one non-card item is present.
    * If only card line items exist (degenerate — `cart_effectively_empty?`
      normally prevents this from reaching `:placed`): falls back to
      `"Order {reference}"`.

  Used as a module calculation on `Edenflowers.Store.Order`:

      calculate :display_title, :string, Edenflowers.Store.Order.Calculations.DisplayTitle
  """
  use Ash.Resource.Calculation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def load(_query, _opts, _context) do
    [
      :order_reference,
      line_items: [:is_card, :product_name, :inserted_at]
    ]
  end

  @impl true
  def calculate(orders, _opts, _context) do
    Enum.map(orders, &title_for/1)
  end

  defp title_for(%{line_items: line_items, order_reference: ref}) when is_list(line_items) do
    non_card =
      line_items
      |> Enum.reject(& &1.is_card)
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)

    case non_card do
      [] ->
        ~t"Order {ref}" |> String.replace("{ref}", ref || "")

      [first] ->
        first.product_name

      [first | rest] ->
        ~t"{name} + {count} more"
        |> String.replace("{name}", first.product_name)
        |> String.replace("{count}", Integer.to_string(length(rest)))
    end
  end

  defp title_for(%{order_reference: ref}),
    do: ~t"Order {ref}" |> String.replace("{ref}", ref || "")
end

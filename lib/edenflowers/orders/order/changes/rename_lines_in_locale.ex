defmodule Edenflowers.Orders.Order.Changes.RenameLinesInLocale do
  @moduledoc """
  Renames a cart's catalogue lines in its new locale, so a customer who adds a
  bouquet in Swedish and pays in Finnish gets a receipt that names it in
  Finnish. Custom lines have no product and keep the name typed for them.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.LineItem
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      rename_lines(order)
      {:ok, order}
    end)
  end

  defp rename_lines(order) do
    lines =
      LineItem
      |> Ash.Query.filter(order_id == ^order.id and not is_nil(product_id))
      |> Ash.Query.load(:product)
      |> Ash.read!(authorize?: false)
      |> Translations.translate_assoc(:product, String.to_existing_atom(order.locale))

    for line <- lines, line.product.name != line.product_name do
      Ash.update!(line, %{product_name: line.product.name}, action: :rename, authorize?: false)
    end
  end
end

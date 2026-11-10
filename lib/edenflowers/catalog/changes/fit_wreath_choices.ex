defmodule Edenflowers.Catalog.Changes.FitWreathChoices do
  @moduledoc """
  Only a wreath offers bows, and a wreath is never a subscription: a
  Subscription doesn't keep the bow colour, so its later deliveries couldn't
  carry one. Moving a product in or out of a wreath category drops whichever
  choice no longer fits, rather than leaving it hidden on its page.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    category_id = Ash.Changeset.get_attribute(changeset, :product_category_id)

    if offers_bows?(category_id),
      do: Ash.Changeset.force_change_attribute(changeset, :subscribable, false),
      else: Ash.Changeset.force_change_attribute(changeset, :bow_colours, [])
  end

  defp offers_bows?(nil), do: false

  defp offers_bows?(category_id),
    do: Ash.get!(Edenflowers.Catalog.ProductCategory, category_id, load: [:offers_bows], authorize?: false).offers_bows
end

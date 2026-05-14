defmodule Edenflowers.Store.Order.Changes.SnapshotPromotion do
  @moduledoc """
  Mirrors selected fields from the assigned `Promotion` onto the order. The
  order's :placed policy then freezes them as the commercial record,
  independent of later edits to the promotion.

  Runs as a `before_action` so it sees the promotion_id that
  `LookupPromotionCode` sets in its own `before_action`, regardless of
  registration order.
  """
  use Ash.Resource.Change

  alias Edenflowers.Store.Promotion

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &snapshot/1)
  end

  defp snapshot(changeset) do
    if Ash.Changeset.changing_attribute?(changeset, :promotion_id) do
      apply_snapshot(changeset)
    else
      changeset
    end
  end

  defp apply_snapshot(changeset) do
    case Ash.Changeset.get_attribute(changeset, :promotion_id) do
      nil ->
        Ash.Changeset.force_change_attributes(changeset,
          discount_percentage: nil,
          promotion_name: nil,
          promotion_code: nil
        )

      id ->
        case Ash.get(Promotion, id, authorize?: false) do
          {:ok, %{discount_percentage: percentage, name: name, code: code}} ->
            Ash.Changeset.force_change_attributes(changeset,
              discount_percentage: percentage,
              promotion_name: name,
              promotion_code: code
            )

          {:error, _} ->
            Ash.Changeset.add_error(changeset,
              field: :promotion_id,
              message: "Invalid promotion"
            )
        end
    end
  end
end

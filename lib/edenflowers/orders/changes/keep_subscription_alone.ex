defmodule Edenflowers.Orders.Changes.KeepSubscriptionAlone do
  @moduledoc """
  A subscription is checked out on its own, one bouquet, so each occurrence's
  fee and VAT come from that one line. A card may still go with it.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Ash.Query

  alias Edenflowers.Orders.LineItem

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &check/1)
  end

  defp check(changeset) do
    if Ash.Changeset.get_attribute(changeset, :is_card) do
      changeset
    else
      order_id = Ash.Changeset.get_attribute(changeset, :order_id)
      subscribable? = Ash.Changeset.get_attribute(changeset, :subscribable)

      others =
        LineItem
        |> Ash.Query.filter(order_id == ^order_id and is_card == false)
        |> Ash.Query.select([:subscribable])
        |> Ash.read!(authorize?: false)

      if others != [] and (subscribable? or Enum.any?(others, & &1.subscribable)) do
        Ash.Changeset.add_error(changeset,
          field: :product_variant_id,
          message: ~t"A subscription is checked out on its own"
        )
      else
        changeset
      end
    end
  end
end

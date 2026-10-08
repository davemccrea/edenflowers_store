defmodule Edenflowers.Orders.Changes.KeepSubscriptionAlone do
  @moduledoc """
  A subscription is checked out on its own, one bouquet, so each occurrence's
  fee and VAT come from that one line. A card may still go with it.

  Adding a subscription to a cart that holds only a subscription replaces it,
  so a customer can change its size or frequency without emptying the cart.
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
      subscription? = not is_nil(Ash.Changeset.get_attribute(changeset, :interval_weeks))

      others =
        LineItem
        |> Ash.Query.filter(order_id == ^order_id and is_card == false)
        |> Ash.read!(authorize?: false)

      cond do
        others == [] ->
          changeset

        subscription? and Enum.all?(others, & &1.interval_weeks) ->
          replace(changeset, others)

        subscription? or Enum.any?(others, & &1.interval_weeks) ->
          Ash.Changeset.add_error(changeset,
            field: :product_variant_id,
            message: ~t"A subscription is checked out on its own"
          )

        true ->
          changeset
      end
    end
  end

  defp replace(changeset, subscription_lines) do
    notifications =
      Enum.flat_map(subscription_lines, fn line_item ->
        {:ok, notifications} =
          Ash.destroy(line_item, action: :remove_item, authorize?: false, return_notifications?: true)

        notifications
      end)

    {changeset, %{notifications: notifications}}
  end
end

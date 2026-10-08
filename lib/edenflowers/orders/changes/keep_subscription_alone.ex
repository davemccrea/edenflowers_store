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
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, &check(&1, context))
  end

  defp check(changeset, context) do
    if Ash.Changeset.get_attribute(changeset, :is_card) do
      changeset
    else
      order_id = Ash.Changeset.get_attribute(changeset, :order_id)

      LineItem
      |> Ash.Query.filter(order_id == ^order_id and is_card == false)
      |> Ash.read(Ash.Context.to_opts(context))
      |> case do
        {:ok, others} -> check_against(changeset, others, context)
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end
  end

  defp check_against(changeset, others, context) do
    subscription? = not is_nil(Ash.Changeset.get_attribute(changeset, :interval_weeks))

    cond do
      others == [] ->
        changeset

      subscription? and Enum.all?(others, & &1.interval_weeks) ->
        replace(changeset, others, context)

      subscription? or Enum.any?(others, & &1.interval_weeks) ->
        Ash.Changeset.add_error(changeset,
          field: :product_variant_id,
          message: ~t"A subscription is checked out on its own. Empty your cart to add this."
        )

      true ->
        changeset
    end
  end

  defp replace(changeset, subscription_lines, context) do
    opts = Ash.Context.to_opts(context, action: :remove_item, return_notifications?: true)

    Enum.reduce_while(subscription_lines, {changeset, %{notifications: []}}, fn line_item, {changeset, acc} ->
      case Ash.destroy(line_item, opts) do
        {:ok, notifications} ->
          {:cont, {changeset, %{notifications: acc.notifications ++ notifications}}}

        {:error, error} ->
          {:halt, Ash.Changeset.add_error(changeset, error)}
      end
    end)
  end
end

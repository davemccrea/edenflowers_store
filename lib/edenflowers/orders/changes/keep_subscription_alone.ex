defmodule Edenflowers.Orders.Changes.KeepSubscriptionAlone do
  @moduledoc """
  A subscription is checked out on its own, one bouquet, so each occurrence's
  fee and VAT come from that one line. A card may still go with it.

  When the cart holds only the product being added and either side is a
  subscription, the add replaces what's there. So a customer can change a
  subscription's size or frequency, or switch between buying once and
  subscribing, without emptying the cart. The product page asks `replaces?/3`
  so its button can say so.
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
    product_id = Ash.Changeset.get_attribute(changeset, :product_id)

    cond do
      others == [] ->
        changeset

      replaces?(others, product_id, subscription?) ->
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

  @doc "Whether adding the product, once or as a subscription, replaces what the cart holds."
  def replaces?(line_items, product_id, subscription?) do
    lines = Enum.reject(line_items, & &1.is_card)

    lines != [] and Enum.all?(lines, &(&1.product_id == product_id)) and
      (subscription? or Enum.any?(lines, & &1.interval_weeks))
  end

  defp replace(changeset, lines, context) do
    opts = Ash.Context.to_opts(context, action: :remove_item, return_notifications?: true)

    Enum.reduce_while(lines, {changeset, %{notifications: []}}, fn line_item, {changeset, acc} ->
      case Ash.destroy(line_item, opts) do
        {:ok, notifications} ->
          {:cont, {changeset, %{notifications: acc.notifications ++ notifications}}}

        {:error, error} ->
          {:halt, Ash.Changeset.add_error(changeset, error)}
      end
    end)
  end
end

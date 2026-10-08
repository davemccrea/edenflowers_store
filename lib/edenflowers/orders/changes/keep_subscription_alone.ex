defmodule Edenflowers.Orders.Changes.KeepSubscriptionAlone do
  @moduledoc """
  A subscription is checked out on its own, one bouquet, so each occurrence's
  fee and VAT come from that one line. A card may still go with it.

  When the cart holds only the product being added and either side is a
  subscription, the add replaces what's there, all but a card. So a customer
  can switch between buying once and subscribing, or change a subscription's
  size or frequency, without emptying the cart. The product page asks
  `replaces?/3` so its button can say so.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Ash.Query

  alias Edenflowers.Orders.LineItem

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, &check(&1, context))
  end

  def replaces?(line_items, product_id, subscription?) do
    lines = Enum.reject(line_items, & &1.is_card)

    lines != [] and Enum.all?(lines, &(&1.product_id == product_id)) and
      (subscription? or Enum.any?(lines, & &1.interval_weeks))
  end

  defp check(changeset, context) do
    if Ash.Changeset.get_attribute(changeset, :is_card) do
      changeset
    else
      changeset
      |> Ash.Changeset.get_attribute(:order_id)
      |> non_card_lines()
      |> Ash.read(Ash.Context.to_opts(context))
      |> case do
        {:ok, lines} -> check_against(changeset, lines, context)
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end
  end

  defp check_against(changeset, lines, context) do
    subscription? = not is_nil(Ash.Changeset.get_attribute(changeset, :interval_weeks))
    product_id = Ash.Changeset.get_attribute(changeset, :product_id)

    cond do
      replaces?(lines, product_id, subscription?) ->
        replace(changeset, context)

      lines != [] and (subscription? or Enum.any?(lines, & &1.interval_weeks)) ->
        Ash.Changeset.add_error(changeset,
          field: :product_variant_id,
          message: ~t"A subscription is checked out on its own. Empty your cart to add this."
        )

      true ->
        changeset
    end
  end

  defp replace(changeset, context) do
    changeset
    |> Ash.Changeset.get_attribute(:order_id)
    |> non_card_lines()
    |> Ash.bulk_destroy(
      :remove_item,
      %{},
      Ash.Context.to_opts(context, strategy: [:atomic, :stream], notify?: true, return_errors?: true)
    )
    |> case do
      %Ash.BulkResult{status: :success} -> changeset
      %Ash.BulkResult{errors: errors} -> Ash.Changeset.add_error(changeset, errors)
    end
  end

  defp non_card_lines(order_id) do
    Ash.Query.filter(LineItem, order_id == ^order_id and is_card == false)
  end
end

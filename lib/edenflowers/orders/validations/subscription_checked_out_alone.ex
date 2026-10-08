defmodule Edenflowers.Orders.Validations.SubscriptionCheckedOutAlone do
  @moduledoc """
  A subscription is checked out on its own, one bouquet, so each occurrence's
  fee and VAT come from that one line. A card may still go with it. An add the
  cart is replaced by (`Order.replaced_by_adding?`) is let through for
  `Changes.ReplaceCart`.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Orders.Order

  @impl true
  def validate(changeset, _opts, context) do
    if Ash.Changeset.get_attribute(changeset, :is_card) do
      :ok
    else
      subscription? = not is_nil(Ash.Changeset.get_attribute(changeset, :interval_weeks))

      case cart(changeset, subscription?, context) do
        {:ok, %Order{non_card_line_item_count: 0}} ->
          :ok

        {:ok, %Order{replaced_by_adding?: true}} ->
          :ok

        {:ok, %Order{subscription?: cart_subscription?}} when subscription? or cart_subscription? ->
          {:error,
           field: :product_variant_id,
           message: ~t"A subscription is checked out on its own. Empty your cart to add this."}

        {:ok, _ordinary_cart} ->
          :ok

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp cart(changeset, subscription?, context) do
    Ash.get(
      Order,
      Ash.Changeset.get_attribute(changeset, :order_id),
      Ash.Context.to_opts(context,
        load: [
          :non_card_line_item_count,
          :subscription?,
          replaced_by_adding?: %{
            product_id: Ash.Changeset.get_attribute(changeset, :product_id),
            subscription?: subscription?
          }
        ]
      )
    )
  end
end

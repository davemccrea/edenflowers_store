defmodule Edenflowers.Orders.Changes.ApplyPromotion do
  @moduledoc """
  Assigns the promotion named by the `code` argument and mirrors the fields
  the order keeps once placed, independent of later edits to the promotion.

  The minimum cart total is checked here so the customer hears about it when
  applying the code. `promotion_applied?` checks it again as the cart changes.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Pricing

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      code = Ash.Changeset.get_argument(changeset, :code)

      case Pricing.get_promotion_by_code(code) do
        {:ok, promotion} -> apply_promotion(changeset, promotion)
        {:error, _error} -> Ash.Changeset.add_error(changeset, field: :code, message: ~t"Invalid code")
      end
    end)
  end

  defp apply_promotion(changeset, promotion) do
    order = Ash.load!(changeset.data, :items_subtotal, authorize?: false)

    if Decimal.compare(order.items_subtotal, promotion.minimum_cart_total) == :lt do
      Ash.Changeset.add_error(changeset,
        field: :code,
        message:
          ~t"Cart total must be at least #{Edenflowers.Format.currency(promotion.minimum_cart_total, order.locale)} to use this promotion"
      )
    else
      Ash.Changeset.force_change_attributes(changeset,
        promotion_id: promotion.id,
        discount_rate: promotion.discount_rate,
        promotion_name: promotion.name,
        promotion_code: to_string(promotion.code),
        promotion_minimum_cart_total: promotion.minimum_cart_total
      )
    end
  end
end

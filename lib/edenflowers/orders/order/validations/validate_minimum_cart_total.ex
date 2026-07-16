defmodule Edenflowers.Orders.Order.Validations.ValidateMinimumCartTotal do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    promotion_id = Ash.Changeset.get_argument_or_attribute(changeset, :promotion_id)

    if is_nil(promotion_id) do
      :ok
    else
      validate_minimum_cart_total(changeset, promotion_id)
    end
  end

  defp validate_minimum_cart_total(changeset, promotion_id) do
    with {:ok, promotion} <- Edenflowers.Pricing.get_promotion_by_id(promotion_id, authorize?: false),
         {:ok, order} <- Ash.load(changeset.data, [:items_subtotal], authorize?: false, lazy?: true) do
      items_subtotal = order.items_subtotal || Decimal.new(0)
      minimum_required = promotion.minimum_cart_total

      if Decimal.compare(items_subtotal, minimum_required) in [:gt, :eq] do
        :ok
      else
        {:error,
         field: :promotion_id,
         message:
           ~t"Cart total must be at least #{Edenflowers.Format.currency(minimum_required, order.locale)} to use this promotion"}
      end
    else
      {:error, _} ->
        {:error, field: :promotion_id, message: ~t"Invalid promotion"}
    end
  end
end

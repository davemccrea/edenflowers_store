defmodule Edenflowers.Store.Order.ValidateMinimumCartTotal do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Utils

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
    with {:ok, promotion} <- Edenflowers.Store.Promotion.get_by_id(promotion_id, authorize?: false),
         {:ok, order} <- Ash.load(changeset.data, [:line_total], authorize?: false) do
      line_total = order.line_total || Decimal.new(0)
      minimum_required = promotion.minimum_cart_total

      if Decimal.compare(line_total, minimum_required) in [:gt, :eq] do
        :ok
      else
        {:error,
         field: :promotion_id,
         message: ~t"Cart total must be at least #{Utils.format_money(minimum_required)} to use this promotion"}
      end
    else
      {:error, _} ->
        {:error, field: :promotion_id, message: ~t"Invalid promotion"}
    end
  end
end

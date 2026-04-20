defmodule Edenflowers.Store.Order.ValidateMinimumCartTotal do
  @moduledoc """
  Validates that the order's line_total meets the promotion's minimum_cart_total requirement.

  This change ensures that promotions can only be applied to orders that meet
  the minimum purchase requirement. If the cart total is below the minimum,
  an error is added to the changeset.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Utils

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      promotion_id = Ash.Changeset.get_argument_or_attribute(changeset, :promotion_id)

      if is_nil(promotion_id) do
        changeset
      else
        validate_minimum_cart_total(changeset, promotion_id)
      end
    end)
  end

  defp validate_minimum_cart_total(changeset, promotion_id) do
    with {:ok, promotion} <- Edenflowers.Store.Promotion.get_by_id(promotion_id, authorize?: false),
         {:ok, order} <- Ash.load(changeset.data, [:line_total], authorize?: false) do
      line_total = order.line_total || Decimal.new(0)
      minimum_required = promotion.minimum_cart_total

      if Decimal.compare(line_total, minimum_required) in [:gt, :eq] do
        changeset
      else
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :promotion_id,
          message: ~t"Cart total must be at least #{Utils.format_money(minimum_required)} to use this promotion"
        })
      end
    else
      {:error, _} ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :promotion_id,
          message: ~t"Invalid promotion"
        })
    end
  end
end

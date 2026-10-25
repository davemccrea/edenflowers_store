defmodule Edenflowers.Orders.LineItem.Changes.SetTaxRate do
  @moduledoc "Charges the line the percentage of the `tax_rate_id` chosen for it."
  use Ash.Resource.Change

  alias Edenflowers.Pricing.TaxRate

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :tax_rate_id) do
      nil ->
        changeset

      id ->
        case Ash.get(TaxRate, id, authorize?: false) do
          {:ok, tax_rate} -> Ash.Changeset.force_change_attribute(changeset, :tax_rate, tax_rate.percentage)
          _ -> Ash.Changeset.add_error(changeset, field: :tax_rate_id, message: "choose a VAT rate")
        end
    end
  end
end

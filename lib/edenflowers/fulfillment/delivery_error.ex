defmodule Edenflowers.Fulfillment.DeliveryError do
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @doc """
  Single source of truth for user-facing delivery-related error messages.
  Used by the address input component (blur-time errors), the
  `CalculateFulfillmentCost` change (submit-time errors), and the
  `ValidateDeliveryAddress` validation (missing address).
  """
  @spec message(atom()) :: String.t()
  def message(:address_required), do: ~t"Delivery address required"
  def message(:address_not_found), do: ~t"Address not found"
  def message(:out_of_delivery_range), do: ~t"Outside delivery range"
  def message(_), do: ~t"There was a problem calculating delivery cost, please try again later"
end

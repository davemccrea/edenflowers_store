defmodule Edenflowers.Store.Order.Validations.RequireDeliveryAddress do
  @moduledoc """
  Validates that a delivery order has a non-blank typed address.

  Runs in the validate phase so it fires on every phx-change and shows errors
  as the user types.

  The companion check that the address was geocoded lives in
  `Edenflowers.Store.Order.Changes.RequireGeocodedAddress` and runs `before_action`,
  since `geocoded_address` is written server-side by the blur handler rather
  than by user input.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    # Argument carries the user's typed value during phx-change; falls back to
    # the persisted attribute (set by confirm_delivery_address on blur).
    typed_address =
      Ash.Changeset.get_argument(changeset, :delivery_address) ||
        Ash.Changeset.get_attribute(changeset, :delivery_address)

    if delivery?(changeset) and blank?(typed_address) do
      {:error, field: :delivery_address, message: ~t"Delivery address required"}
    else
      :ok
    end
  end

  defp delivery?(changeset) do
    Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
end

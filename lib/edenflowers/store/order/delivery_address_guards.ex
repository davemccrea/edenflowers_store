defmodule Edenflowers.Store.Order.DeliveryAddressGuards do
  @moduledoc """
  Two-phase guards that together ensure a delivery order only advances past
  step 3 with a valid, geocoded address.

  The field is filled in two phases, so the check runs in two phases:

    1. `Validate` runs during `phx-change` — fires on every keystroke,
       so the user sees "required" feedback while typing.
    2. `ChangeGeocoded` runs `before_action` — fires only on submit, and
       checks the persisted `geocoded_address` attribute. Must be a change
       rather than a validation because `geocoded_address` is written
       server-side by the blur handler, not from form params, so during
       phx-change it would always look missing.
  """

  defmodule Validate do
    @moduledoc """
    Validates that a delivery order has a non-blank typed address.

    See `Edenflowers.Store.Order.DeliveryAddressGuards` for the companion
    submit-time check.
    """
    use Ash.Resource.Validation
    use GettextSigils, backend: EdenflowersWeb.Gettext

    @impl true
    def validate(changeset, _opts, _context) do
      typed =
        Ash.Changeset.get_argument(changeset, :delivery_address) ||
          Ash.Changeset.get_attribute(changeset, :delivery_address)

      if delivery?(changeset) and blank?(typed) do
        {:error, field: :delivery_address, message: ~t"Delivery address required"}
      else
        :ok
      end
    end

    defp delivery?(changeset),
      do: Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery

    defp blank?(nil), do: true
    defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  end

  defmodule ChangeGeocoded do
    @moduledoc """
    Submit-time guard: delivery orders must have a geocoded address + amount.

    See `Edenflowers.Store.Order.DeliveryAddressGuards` for the companion
    phx-change check.
    """
    use Ash.Resource.Change
    use GettextSigils, backend: EdenflowersWeb.Gettext

    @impl true
    def change(changeset, _opts, _context) do
      Ash.Changeset.before_action(changeset, fn changeset ->
        if delivery?(changeset) and not geocoded?(changeset) do
          Ash.Changeset.add_error(changeset,
            field: :delivery_address,
            message: ~t"Delivery address required"
          )
        else
          changeset
        end
      end)
    end

    defp delivery?(changeset),
      do: Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery

    defp geocoded?(changeset) do
      not is_nil(Ash.Changeset.get_attribute(changeset, :geocoded_address)) and
        not is_nil(Ash.Changeset.get_attribute(changeset, :fulfillment_amount))
    end
  end
end

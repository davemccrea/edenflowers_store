defmodule Edenflowers.Orders.Validations.SubscriptionDeliveryDay do
  @moduledoc """
  A subscription moves only to a weekday the shop is open on.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillment

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :delivery_day) do
      nil ->
        :ok

      day ->
        if day in Fulfillment.get_shop_calendar!(authorize?: false).available_days, do: :ok, else: error()
    end
  end

  defp error, do: {:error, field: :delivery_day, message: ~t"Choose one of the days on offer."}
end

defmodule Edenflowers.Orders.Subscription.Validations.SubscriptionDeliveryDay do
  @moduledoc """
  A subscription moves only to one of its `delivery_days`.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :delivery_day) do
      nil ->
        :ok

      day ->
        subscription = Ash.load!(changeset.data, :delivery_days, authorize?: false, reuse_values?: false)
        if day in subscription.delivery_days, do: :ok, else: error()
    end
  end

  defp error, do: {:error, field: :delivery_day, message: ~t"Choose one of the days on offer."}
end

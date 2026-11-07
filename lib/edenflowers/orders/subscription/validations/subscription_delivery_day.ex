defmodule Edenflowers.Orders.Subscription.Validations.SubscriptionDeliveryDay do
  @moduledoc """
  A subscription moves only to one of its `delivery_days`.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :delivery_day) do
      day = Ash.Changeset.get_attribute(changeset, :delivery_day)
      subscription = Ash.load!(changeset.data, :delivery_days, authorize?: false, reuse_values?: false)
      if day in subscription.delivery_days, do: :ok, else: error()
    else
      :ok
    end
  end

  defp error, do: {:error, field: :delivery_day, message: ~t"Choose one of the days on offer."}
end

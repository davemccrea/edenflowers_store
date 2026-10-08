defmodule Edenflowers.Orders.Validations.SubscriptionDeliveryDay do
  @moduledoc """
  A subscription moves only to a weekday its delivery option runs on.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, context) do
    case Ash.Changeset.get_argument(changeset, :delivery_day) do
      nil ->
        :ok

      day ->
        case Ash.load(changeset.data, :fulfillment_option, Ash.Context.to_opts(context, authorize?: false)) do
          {:ok, %{fulfillment_option: %{available_days: days}}} ->
            if day in days, do: :ok, else: error()

          _error ->
            error()
        end
    end
  end

  defp error, do: {:error, field: :delivery_day, message: ~t"Choose one of the days we deliver on."}
end

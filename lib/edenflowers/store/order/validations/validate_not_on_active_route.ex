defmodule Edenflowers.Store.Order.Validations.ValidateNotOnActiveRoute do
  @moduledoc """
  Blocks rescheduling while the order is assigned to a stop on a route dated
  today or later. Stops on earlier (expired) routes — e.g. a failed delivery from
  a previous day — don't block it.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    order_id = changeset.data.id
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

    assigned? =
      Edenflowers.Store.DeliveryStop
      |> Ash.Query.filter(order_id == ^order_id and delivery_trip.delivery_route.delivery_date >= ^today)
      |> Ash.read!(authorize?: false)
      |> Enum.any?()

    if assigned? do
      {:error, field: :fulfillment_date, message: ~t"Cannot reschedule a delivery that is assigned to an active route"}
    else
      :ok
    end
  end
end

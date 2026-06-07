defmodule Edenflowers.Delivery.Route.Validations.AllStopsPending do
  use Ash.Resource.Validation

  require Ash.Query

  alias Edenflowers.Delivery.RouteStop

  @impl true
  def validate(changeset, _opts, _context) do
    route_id = Ash.Changeset.get_data(changeset, :id)

    started? =
      RouteStop
      |> Ash.Query.filter(route_id == ^route_id and status != :pending)
      |> Ash.exists?(authorize?: false)

    if started?,
      do: {:error, field: :route_stops, message: "trip has already started"},
      else: :ok
  end
end

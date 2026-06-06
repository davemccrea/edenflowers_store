defmodule EdenflowersWeb.DeliveryRouteShared do
  @moduledoc """
  Shared loading, row-building, and outcome-recording logic for the two delivery
  route pages — the public secret-link page for drivers and the authenticated
  admin monitoring page. Both render through `DeliveryRouteComponents` and differ
  only in how they authorize and who is recorded as the actor.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Ash.Query

  alias Edenflowers.Dispatch
  alias Edenflowers.Store.DeliveryRoute

  @order_load [
    :order_reference,
    :recipient_name,
    :recipient_phone_number,
    :delivery_address,
    :delivery_instructions,
    :card_message,
    :position,
    :payment_status,
    :fulfillment_status,
    line_items: [:product_name, :variant_size, :quantity, :is_card]
  ]

  @doc "Loads a route with everything the page renders, or nil."
  def load_route(route_id) do
    DeliveryRoute
    |> Ash.Query.filter(id == ^route_id)
    |> Ash.Query.load([:driver, trips: [stops: [:attempts, order: @order_load]]])
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, route} -> route
      _ -> nil
    end
  end

  @doc "Looks up a route by the SHA-256 hash of the presented raw token."
  def load_route_by_token(raw_token) do
    case DeliveryRoute.by_token_hash(Dispatch.hash_token(raw_token), authorize?: false) do
      {:ok, %DeliveryRoute{} = route} -> load_route(route.id)
      _ -> nil
    end
  end

  @doc """
  Flattens a route's trips into ordered display rows, deriving a return-to-shop
  row before each supplemental trip.
  """
  def build_rows(route) do
    route.trips
    |> Enum.sort_by(& &1.sequence)
    |> Enum.with_index()
    |> Enum.flat_map(fn {trip, index} ->
      return_rows(trip, index) ++ stop_rows(trip)
    end)
  end

  defp return_rows(%{return_leg_distance: nil}, _index), do: []
  defp return_rows(_trip, 0), do: []

  defp return_rows(trip, _index) do
    [{:return, %{distance: trip.return_leg_distance, duration: trip.return_leg_duration}}]
  end

  defp stop_rows(trip) do
    trip.stops |> Enum.sort_by(& &1.sequence) |> Enum.map(&{:stop, &1})
  end

  @doc "True once every stop is delivered or cancelled (refunded)."
  def route_complete?(route) do
    stops = route.trips |> Enum.flat_map(& &1.stops)
    stops != [] and Enum.all?(stops, &(delivered?(&1) or cancelled?(&1)))
  end

  def delivered?(stop), do: stop.order.fulfillment_status == :fulfilled
  def cancelled?(stop), do: stop.order.payment_status == :refunded
  def pending?(stop), do: not delivered?(stop) and not cancelled?(stop)

  @doc "Most recent failed attempt for a stop, for retry context (photo excluded)."
  def latest_failed_attempt(stop) do
    stop.attempts
    |> Enum.filter(&(&1.outcome == :failed))
    |> Enum.sort_by(& &1.recorded_at, {:desc, DateTime})
    |> List.first()
  end

  @doc "Google Maps directions to a `\"lat,lng\"` destination using current location as origin."
  def maps_url(position) when is_binary(position) do
    "https://www.google.com/maps/dir/?api=1&destination=#{URI.encode(position)}&travelmode=driving"
  end

  def shop_maps_url do
    %{lat: lat, lng: lng} = Dispatch.shop_position()
    maps_url("#{lat},#{lng}")
  end

  @doc """
  Records the outcome for the stop currently open in the dialog, attributing it
  to the given actor (`:driver_link` or `:admin`). Reloads the route and closes
  the dialog on success; surfaces validation and expiry as flashes.
  """
  def submit_outcome(params, socket, actor_info) do
    attrs = params |> parse_outcome_params() |> Map.merge(actor_info)

    case Dispatch.record_outcome(socket.assigns.active_stop_id, attrs) do
      {:ok, _attempt} ->
        socket
        |> reload_route()
        |> assign(:active_stop_id, nil)
        |> put_flash(:info, ~t"Outcome recorded.")

      {:error, :expired} ->
        socket
        |> assign(:expired?, true)
        |> assign(:active_stop_id, nil)
        |> put_flash(:error, ~t"This route has expired.")

      {:error, _reason} ->
        put_flash(socket, :error, ~t"Could not record the outcome. Check the form and try again.")
    end
  end

  @doc "Finds a stop by id within a loaded route."
  def find_stop(route, stop_id) do
    route.trips |> Enum.flat_map(& &1.stops) |> Enum.find(&(&1.id == stop_id))
  end

  @doc "Reloads the route data and recomputes derived rows/completion."
  def reload_route(socket) do
    route = load_route(socket.assigns.route.id)
    assign_route(socket, route)
  end

  @doc "Assigns a loaded route plus its derived display state."
  def assign_route(socket, route) do
    socket
    |> assign(:route, route)
    |> assign(:rows, build_rows(route))
    |> assign(:complete?, route_complete?(route))
  end

  # Whitelist user-supplied enum values rather than String.to_atom on input.
  defp parse_outcome_params(params) do
    %{
      outcome: outcome(params["outcome"]),
      delivered_method: delivered_method(params["delivered_method"]),
      failure_reason: failure_reason(params["failure_reason"]),
      note: blank_to_nil(params["note"])
    }
  end

  defp outcome("delivered"), do: :delivered
  defp outcome(_), do: :failed

  @methods ~w(handed_to_recipient left_in_safe_place other)
  defp delivered_method(value) when value in @methods, do: String.to_existing_atom(value)
  defp delivered_method(_), do: nil

  @reasons ~w(recipient_unavailable could_not_access_address could_not_find_address recipient_refused other)
  defp failure_reason(value) when value in @reasons, do: String.to_existing_atom(value)
  defp failure_reason(_), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str), do: String.trim(str)
end

defmodule Edenflowers.Dispatch.Result do
  @moduledoc "What a publication produced: the batch and one entry per assigned driver."
  @enforce_keys [:batch, :routes]
  defstruct [:batch, :routes]
end

defmodule Edenflowers.Dispatch do
  @moduledoc """
  Atomic publication of an optimized delivery plan.

  HERE optimization happens before this module is ever called; only persistence
  is transactional, so no database transaction is ever held open across the HERE
  request. In one transaction this creates the batch, finds or creates each
  driver's daily route, appends one immutable trip with its ordered stops and leg
  metrics, and (for a brand-new external route) stores a SHA-256 token hash. The
  raw token is returned to the caller for building the email URL and is never
  persisted or logged. After commit, one email job is enqueued per newly created
  route and route/batch events are broadcast.
  """
  require Logger

  alias Edenflowers.Repo

  alias Edenflowers.Store.{
    DeliveryBatch,
    DeliveryRoute,
    DeliveryStop,
    DeliveryTrip
  }

  alias Edenflowers.HereTourPlanning.Plan
  alias Edenflowers.Workers.SendDriverRouteEmail

  @system %{system: true}

  # The shop is the start of every route, matching HereAPI's geocoding origin.
  @shop %{lat: 63.1243488, lng: 21.5974075}

  @doc "Shop coordinates — the start location for every optimized route."
  def shop_position, do: @shop

  @doc """
  Publishes `plan` for `delivery_date`.

  Options:
    * `:return_legs` — `%{driver_id => %{distance:, duration:}}`, the leg from a
      driver's previous final stop back to the shop, persisted on a supplemental
      trip. Ignored for a driver receiving their first trip of the day.
  """
  def publish(%Plan{} = plan, %{delivery_date: date, published_by_user_id: user_id} = attrs) do
    return_legs = Map.get(attrs, :return_legs, %{})

    result =
      Repo.transaction(fn ->
        with :ok <- reject_already_assigned(plan, date),
             {:ok, batch} <- create_batch(date, user_id),
             {:ok, routes} <- publish_assignments(plan, batch, date, return_legs) do
          %Edenflowers.Dispatch.Result{batch: batch, routes: routes}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, %Edenflowers.Dispatch.Result{} = data} ->
        after_commit(data)
        {:ok, data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_batch(date, user_id) do
    DeliveryBatch
    |> Ash.Changeset.for_create(
      :create,
      %{delivery_date: date, published_by_user_id: user_id, published_at: DateTime.utc_now()},
      actor: @system
    )
    |> insert()
  end

  defp publish_assignments(%Plan{assignments: assignments}, batch, date, return_legs) do
    Enum.reduce_while(assignments, {:ok, []}, fn assignment, {:ok, acc} ->
      case publish_assignment(assignment, batch, date, return_legs) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, routes} -> {:ok, Enum.reverse(routes)}
      error -> error
    end
  end

  defp publish_assignment(assignment, batch, date, return_legs) do
    driver_id = assignment.vehicle_id

    with {:ok, {route, raw_token, new?}} <- find_or_create_route(driver_id, date),
         {:ok, sequence} <- next_sequence(route, new?),
         return_leg = if(new?, do: nil, else: Map.get(return_legs, driver_id)),
         {:ok, trip} <- create_trip(route, batch, assignment, sequence, return_leg),
         {:ok, _stops} <- create_stops(trip, assignment.stops) do
      {:ok, %{driver_id: driver_id, route: route, trip: trip, raw_token: raw_token, new?: new?}}
    end
  end

  defp find_or_create_route(driver_id, date) do
    require Ash.Query

    existing =
      DeliveryRoute
      |> Ash.Query.filter(driver_id == ^driver_id and delivery_date == ^date)
      |> Ash.read_one(authorize?: false)

    case existing do
      {:ok, %DeliveryRoute{} = route} ->
        {:ok, {route, nil, false}}

      {:ok, nil} ->
        raw_token = generate_token()

        DeliveryRoute
        |> Ash.Changeset.for_create(
          :create,
          %{
            delivery_date: date,
            driver_id: driver_id,
            token_hash: hash_token(raw_token),
            first_published_at: DateTime.utc_now()
          },
          actor: @system
        )
        |> insert()
        |> case do
          {:ok, route} -> {:ok, {route, raw_token, true}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp next_sequence(_route, true), do: {:ok, 1}

  defp next_sequence(route, false) do
    require Ash.Query

    DeliveryTrip
    |> Ash.Query.filter(delivery_route_id == ^route.id)
    |> Ash.Query.sort(sequence: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:ok, 1}
      {:ok, %DeliveryTrip{sequence: max}} -> {:ok, max + 1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_trip(route, batch, assignment, sequence, return_leg) do
    DeliveryTrip
    |> Ash.Changeset.for_create(
      :create,
      %{
        delivery_route_id: route.id,
        batch_id: batch.id,
        sequence: sequence,
        distance: assignment.total_distance,
        driving_duration: assignment.total_driving_duration,
        service_duration: assignment.total_service_duration,
        return_leg_distance: return_leg && return_leg.distance,
        return_leg_duration: return_leg && return_leg.duration,
        published_at: DateTime.utc_now()
      },
      actor: @system
    )
    |> insert()
  end

  defp create_stops(trip, stops) do
    Enum.reduce_while(stops, {:ok, []}, fn stop, {:ok, acc} ->
      DeliveryStop
      |> Ash.Changeset.for_create(
        :create,
        %{
          delivery_trip_id: trip.id,
          order_id: stop.order_id,
          sequence: stop.sequence,
          leg_distance: stop.leg_distance,
          leg_duration: stop.leg_duration
        },
        actor: @system
      )
      |> insert()
      |> case do
        {:ok, created} -> {:cont, {:ok, [created | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Atomic re-check: an order must not already sit on a stop dated on or after
  # this publication's date. Eligibility filters these out, but this guards races
  # between preview and publish.
  defp reject_already_assigned(%Plan{assignments: assignments}, date) do
    require Ash.Query

    order_ids =
      assignments
      |> Enum.flat_map(fn a -> Enum.map(a.stops, & &1.order_id) end)

    clashing =
      DeliveryStop
      |> Ash.Query.filter(order_id in ^order_ids and delivery_trip.delivery_route.delivery_date >= ^date)
      |> Ash.read!(authorize?: false)

    case clashing do
      [] -> :ok
      stops -> {:error, {:orders_already_assigned, Enum.map(stops, & &1.order_id)}}
    end
  end

  defp after_commit(%Edenflowers.Dispatch.Result{batch: batch, routes: routes}) do
    Enum.each(routes, fn entry ->
      if entry.new? and entry.raw_token do
        enqueue_email(entry)
      end

      broadcast({:trip_appended, entry.route.id, entry.trip.id}, "delivery_route:#{entry.route.id}")
    end)

    broadcast({:batch_published, batch.id}, "deliveries:#{batch.delivery_date}")
  end

  defp enqueue_email(entry) do
    case SendDriverRouteEmail.enqueue(%{
           "delivery_route_id" => entry.route.id,
           "token" => entry.raw_token
         }) do
      {:ok, _job} ->
        DeliveryRoute.mark_email_queued(entry.route, actor: @system)

      {:error, reason} ->
        Logger.error("Failed to enqueue driver route email for route #{entry.route.id}: #{inspect(reason)}")
    end
  end

  defp broadcast(message, topic) do
    Phoenix.PubSub.broadcast(Edenflowers.PubSub, topic, message)
  end

  # Creates run inside the ambient Repo transaction. None of the dispatch
  # resources declare notifiers, so we take ownership of the (empty) notification
  # batch to avoid Ash's in-transaction "missed notifications" warning.
  defp insert(changeset) do
    case Ash.create(changeset, return_notifications?: true) do
      {:ok, record, _notifications} -> {:ok, record}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  def hash_token(raw), do: :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
end

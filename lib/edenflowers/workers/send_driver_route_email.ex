defmodule Edenflowers.Workers.SendDriverRouteEmail do
  @moduledoc """
  Sends a driver the secret link to their daily route on their first assignment
  for that date. The unique key on `delivery_route_id` makes repeated enqueues
  for the same daily route collapse to one job, so supplemental trips never
  trigger another email.

  The raw token arrives in the job args (the only place it lives outside the
  generated URL) and is used to build the link; it is never logged.
  """
  use Oban.Worker,
    queue: :default,
    unique: [keys: [:delivery_route_id], period: :infinity]

  import Edenflowers.Actors

  alias Edenflowers.{Email, Format, Mailer}
  alias Edenflowers.Store.DeliveryRoute

  def enqueue(%{"delivery_route_id" => route_id} = args) do
    args
    |> __MODULE__.new()
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job}
      {:error, changeset} -> {:error, {:enqueue_failed, route_id, changeset}}
    end
  end

  def perform(%Oban.Job{args: %{"delivery_route_id" => route_id, "token" => token}}) do
    route =
      DeliveryRoute.get_by_id!(route_id,
        actor: system_actor(),
        load: [:driver, trips: [:stops]]
      )

    driver = route.driver
    locale = driver.preferred_locale

    stops = route.trips |> Enum.flat_map(& &1.stops)
    distance = route.trips |> Enum.map(& &1.distance) |> Enum.sum()
    duration = route.trips |> Enum.map(&(&1.driving_duration + &1.service_duration)) |> Enum.sum()

    assigns = %{
      driver_name: driver.name,
      date_str: Format.date(route.delivery_date, locale),
      stop_count: length(stops),
      distance_str: Format.km(distance),
      duration_str: Format.minutes(duration),
      url: route_url(token)
    }

    case driver |> Email.driver_route(assigns) |> Mailer.deliver() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp route_url(token), do: EdenflowersWeb.Endpoint.url() <> "/deliveries/" <> token
end

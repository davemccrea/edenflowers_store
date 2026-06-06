defmodule EdenflowersWeb.DeliveryRouteLive do
  @moduledoc """
  Public driver route page reached through a high-entropy secret link. The raw
  token in the URL is hashed and matched against the stored hash; access is by
  token, not by user. Date validity is rechecked on every mutating event by the
  outcome orchestration, so a link cannot be used after its date.
  """
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.DeliveryRouteComponents

  alias EdenflowersWeb.DeliveryRouteShared, as: Shared

  @timezone "Europe/Helsinki"

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Shared.load_route_by_token(token) do
      nil ->
        {:ok, assign(socket, route: nil, page_title: gettext("Delivery route"))}

      route ->
        Gettext.put_locale(EdenflowersWeb.Gettext, route.driver.preferred_locale)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Edenflowers.PubSub, "delivery_route:#{route.id}")
        end

        {:ok,
         socket
         |> assign(:page_title, gettext("Delivery route"))
         |> assign(:locale, route.driver.preferred_locale)
         |> assign(:actor_info, %{actor_kind: :driver_link})
         |> assign(:active_stop_id, nil)
         |> assign(:active_stop, nil)
         |> assign(:outcome, "delivered")
         |> assign(:expired?, route.delivery_date != today())
         |> Shared.assign_route(route)}
    end
  end

  @impl true
  def handle_event("open_outcome", %{"stop-id" => stop_id}, socket) do
    {:noreply,
     socket
     |> assign(:active_stop_id, stop_id)
     |> assign(:active_stop, Shared.find_stop(socket.assigns.route, stop_id))
     |> assign(:outcome, "delivered")}
  end

  def handle_event("close_outcome", _params, socket) do
    {:noreply, assign(socket, active_stop_id: nil, active_stop: nil)}
  end

  def handle_event("change_outcome", %{"outcome" => outcome}, socket) do
    {:noreply, assign(socket, :outcome, outcome)}
  end

  def handle_event("record_outcome", params, socket) do
    {:noreply, Shared.submit_outcome(params, socket, socket.assigns.actor_info)}
  end

  @impl true
  def handle_info({event, _route_id}, socket) when event in [:route_progress, :trip_appended] do
    {:noreply, Shared.reload_route(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp today, do: DateTime.now!(@timezone) |> DateTime.to_date()

  @impl true
  def render(%{route: nil} = assigns) do
    ~H"""
    <div class="mx-auto max-w-xl px-4 py-16 text-center">
      <.icon name="hero-exclamation-triangle" class="text-warning mx-auto h-10 w-10" />
      <h1 class="mt-4 text-lg font-semibold">{~t"This delivery link is not valid."}</h1>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <.flash kind={:info} flash={@flash} />
    <.flash kind={:error} flash={@flash} />
    <.route_page
      route={@route}
      rows={@rows}
      complete?={@complete?}
      expired?={@expired?}
      active_stop={@active_stop}
      outcome={@outcome}
      locale={@locale}
    />
    """
  end
end

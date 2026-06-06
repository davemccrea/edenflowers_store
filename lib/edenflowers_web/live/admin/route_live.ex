defmodule EdenflowersWeb.Admin.RouteLive do
  @moduledoc """
  Authenticated admin view of a driver's (or any) route. Renders through the same
  components as the public driver page and lets an admin record outcomes on a
  driver's behalf — attributed to the acting admin. No secret token is involved.
  """
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.DeliveryRouteComponents

  alias EdenflowersWeb.DeliveryRouteShared, as: Shared
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @timezone "Europe/Helsinki"

  @impl true
  def mount(%{"id" => route_id}, _session, socket) do
    case Shared.load_route(route_id) do
      nil ->
        {:ok, assign(socket, route: nil, page_title: ~t"Route")}

      route ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Edenflowers.PubSub, "delivery_route:#{route.id}")
        end

        {:ok,
         socket
         |> assign(:page_title, ~t"Route")
         |> assign(:locale, Localize.get_locale())
         |> assign(:actor_info, %{actor_kind: :admin, recorded_by_user_id: socket.assigns.current_user.id})
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
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <div class="px-4 py-16 text-center">
        <h1 class="text-lg font-semibold">{~t"Route not found"}</h1>
      </div>
    </Layouts.admin>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.route_page
        route={@route}
        rows={@rows}
        complete?={@complete?}
        expired?={@expired?}
        active_stop={@active_stop}
        outcome={@outcome}
        locale={@locale}
      />
    </Layouts.admin>
    """
  end
end

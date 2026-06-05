defmodule EdenflowersWeb.Admin.FulfillmentCalendarLive do
  @moduledoc """
  Admin date-toggle editor.

  The florist sees a calendar overlaid on the existing fulfillment-option
  availability rules and can click dates / weekday headers to enable or
  disable them. Scoped to a single fulfillment option or to all options at
  once (with a `:mixed` indicator when options disagree).

  Click semantics live in `Edenflowers.Store.FulfillmentCalendar`. Admin
  presentation lives in `EdenflowersWeb.Admin.CalendarComponent`. This
  LiveView only orchestrates state and persistence.
  """
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.CalendarComponent, only: [admin_calendar: 1, admin_calendar_legend: 1]
  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts

  alias Edenflowers.Store.{FulfillmentCalendar, FulfillmentOption}

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @timezone "Europe/Helsinki"

  @impl true
  def mount(_params, _session, socket) do
    options = FulfillmentOption.list!()

    {:ok,
     socket
     |> assign(:page_title, "Fulfillment Calendar")
     |> assign(:options, options)
     |> assign(:scope, :all)
     |> assign(:today, today())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="wide">
        <.admin_page_header title="Fulfillment Calendar"></.admin_page_header>

        <section class="mb-6 flex flex-wrap gap-2" aria-label="Fulfillment option scope">
          <button
            type="button"
            phx-click="set-scope"
            phx-value-scope="all"
            class={["btn btn-sm", if(@scope == :all, do: "btn-primary", else: "btn-ghost")]}
          >
            All options
          </button>
          <button
            :for={option <- @options}
            type="button"
            phx-click="set-scope"
            phx-value-scope={option.id}
            class={["btn btn-sm", if(@scope == option.id, do: "btn-primary", else: "btn-ghost")]}
          >
            {option.name}
          </button>
        </section>

        <div class="flex flex-col gap-8 md:flex-row md:items-start">
          <div class="w-full max-w-xl">
            <.admin_calendar
              id="admin-fulfillment-calendar"
              scope={@scope}
              options={@options}
              today={@today}
            />
          </div>

          <div class="flex flex-col gap-4">
            <.admin_calendar_legend />
            <button
              type="button"
              phx-click="reset-calendar"
              data-confirm={reset_confirm_message()}
              aria-label="Reset calendar to defaults"
              class="btn btn-sm btn-ghost text-error hover:bg-error/10"
            >
              Reset
            </button>
          </div>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("set-scope", %{"scope" => "all"}, socket) do
    {:noreply, assign(socket, :scope, :all)}
  end

  def handle_event("set-scope", %{"scope" => id}, socket) do
    {:noreply, assign(socket, :scope, id)}
  end

  def handle_event("reset-calendar", _, socket) do
    {:noreply, apply_to_scope(socket, &FulfillmentOption.reset_calendar!(&1, actor: &2))}
  end

  @impl true
  def handle_info({:fulfillment_date_toggled, date}, socket) do
    {:noreply, apply_to_scope(socket, &FulfillmentOption.toggle_date!(&1, date, actor: &2))}
  end

  def handle_info({:fulfillment_weekday_toggled, weekday}, socket) do
    targets = scoped_options(socket)
    direction = FulfillmentCalendar.weekday_toggle_direction(targets, weekday)

    {:noreply, apply_to_scope(socket, &FulfillmentOption.set_weekday!(&1, weekday, direction, actor: &2))}
  end

  def handle_info({:fulfillment_week_toggled, week}, socket) do
    %{today: today} = socket.assigns
    targets = scoped_options(socket)

    case FulfillmentCalendar.week_toggle_direction(targets, week, today) do
      nil ->
        # Whole week is in the past — nothing to do.
        {:noreply, socket}

      direction ->
        {:noreply, apply_to_scope(socket, &FulfillmentOption.set_week!(&1, week, today, direction, actor: &2))}
    end
  end

  defp scoped_options(%{assigns: %{scope: scope, options: options}}),
    do: FulfillmentCalendar.scoped_options(scope, options)

  defp apply_to_scope(socket, fun) do
    %{options: options, current_user: actor} = socket.assigns
    targets = scoped_options(socket)

    updated_by_id = Map.new(targets, fn option -> {option.id, fun.(option, actor)} end)

    assign(socket, :options, Enum.map(options, &Map.get(updated_by_id, &1.id, &1)))
  end

  defp today, do: @timezone |> DateTime.now!() |> DateTime.to_date()

  defp reset_confirm_message, do: "Are you sure you want to reset the calendar? This action is destructive."
end

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
    <div class="container mx-auto py-10">
      <header class="mb-8 max-w-2xl">
        <p class="eyebrow text-base-content/55 mb-2">Availability</p>
        <h1 class="page-title">Fulfillment Calendar</h1>
        <p class="text-base-content/70 mt-3 text-sm leading-relaxed">
          Click a date to toggle it on or off. Click a weekday header (Mon, Tue&hellip;) to toggle that weekday everywhere.
        </p>
      </header>

      <section class="mb-6 flex flex-wrap gap-2" aria-label="Fulfillment option scope">
        <button
          type="button"
          phx-click="set-scope"
          phx-value-scope="all"
          class={scope_button_class(@scope == :all)}
        >
          All options
        </button>
        <button
          :for={option <- @options}
          type="button"
          phx-click="set-scope"
          phx-value-scope={option.id}
          class={scope_button_class(@scope == option.id)}
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

        <.admin_calendar_legend />
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("set-scope", %{"scope" => "all"}, socket) do
    {:noreply, assign(socket, :scope, :all)}
  end

  def handle_event("set-scope", %{"scope" => id}, socket) do
    {:noreply, assign(socket, :scope, id)}
  end

  @impl true
  def handle_info({:fulfillment_date_toggled, date}, socket) do
    {:noreply, apply_to_scope(socket, &FulfillmentOption.toggle_date!(&1, date, actor: &2))}
  end

  def handle_info({:fulfillment_weekday_toggled, weekday}, socket) do
    if FulfillmentCalendar.weekday_state(socket.assigns.scope, socket.assigns.options, weekday) == :mixed do
      {:noreply, socket}
    else
      {:noreply, apply_to_scope(socket, &FulfillmentOption.toggle_weekday!(&1, weekday, actor: &2))}
    end
  end

  defp apply_to_scope(socket, fun) do
    %{scope: scope, options: options, current_user: actor} = socket.assigns

    targets =
      case scope do
        :all -> options
        id -> Enum.filter(options, &(&1.id == id))
      end

    updated_by_id = Map.new(targets, fn option -> {option.id, fun.(option, actor)} end)

    assign(socket, :options, Enum.map(options, &Map.get(updated_by_id, &1.id, &1)))
  end

  defp today, do: @timezone |> DateTime.now!() |> DateTime.to_date()

  defp scope_button_class(true) do
    "rounded border border-primary bg-primary text-primary-content px-3.5 py-1.5 text-sm font-medium " <>
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-base-content"
  end

  # Inactive chip uses the same hover (`bg-primary/10`) as cells and weekday
  # headers in CalendarComponent so the whole page reads as one interaction system.
  defp scope_button_class(false) do
    "rounded border border-base-content/20 px-3.5 py-1.5 text-sm text-base-content/65 " <>
      "hover:border-primary/40 hover:text-base-content/85 hover:bg-primary/10 " <>
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-base-content"
  end
end

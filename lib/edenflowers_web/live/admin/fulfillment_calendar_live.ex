defmodule EdenflowersWeb.Admin.FulfillmentCalendarLive do
  @moduledoc """
  Admin date-toggle editor.

  The florist sees a calendar overlaid on the existing fulfillment-option
  availability rules and can click dates / weekday headers to enable or
  disable them. Scoped to a single fulfillment option or to all options at
  once (with a `:mixed` indicator when options disagree).

  All click semantics live in `Edenflowers.Store.FulfillmentCalendar`; this
  LiveView only orchestrates state and persistence.
  """
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.{FulfillmentCalendar, FulfillmentOption}

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    options = FulfillmentOption.list!()

    {:ok,
     socket
     |> assign(:page_title, "Fulfillment Calendar")
     |> assign(:options, options)
     |> assign(:scope, :all)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <header class="mb-6">
        <h1 class="text-2xl font-semibold">Fulfillment Calendar</h1>
        <p class="text-base-content/70 mt-1 text-sm">
          Click a date to toggle it on/off. Click a weekday header (Mon, Tue&hellip;) to toggle that weekday everywhere.
        </p>
      </header>

      <section class="mb-4 flex flex-wrap gap-2" aria-label="Fulfillment option scope">
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

      <div class="flex flex-col gap-6 md:flex-row md:items-start">
        <div class="w-full max-w-2xl">
          <.live_component
            id="admin-fulfillment-calendar"
            field={nil}
            module={EdenflowersWeb.CalendarComponent}
            selected_date={nil}
            cell_state={fn date -> current_cell_state(@scope, @options, date) end}
            cell_class={&admin_cell_class/3}
            clickable_states={[:open, :weekday_off, :override_off]}
            on_click={:fulfillment_date_toggled}
            on_weekday_click={:fulfillment_weekday_toggled}
            weekday_class={fn weekday -> admin_weekday_class(weekday_state(@scope, @options, weekday)) end}
          />
        </div>

        <aside class="text-sm">
          <h2 class="mb-2 font-semibold">Legend</h2>
          <ul class="space-y-1">
            <li><span class={legend_swatch(:closed)}></span> Closed</li>
            <li><span class={legend_swatch(:mixed)}></span> Mixed (options disagree)</li>
          </ul>
        </aside>
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
    {:noreply, apply_to_scope(socket, &FulfillmentCalendar.toggle_date(&1, date))}
  end

  def handle_info({:fulfillment_weekday_toggled, weekday}, socket) do
    if weekday_state(socket.assigns.scope, socket.assigns.options, weekday) == :mixed do
      {:noreply, socket}
    else
      {:noreply, apply_to_scope(socket, &FulfillmentCalendar.toggle_weekday(&1, weekday))}
    end
  end

  defp apply_to_scope(%{assigns: %{scope: :all, options: options, current_user: actor}} = socket, fun) do
    options
    |> Enum.map(&persist(&1, fun.(&1), actor))
    |> reload(socket)
  end

  defp apply_to_scope(%{assigns: %{scope: id, options: options, current_user: actor}} = socket, fun) do
    case Enum.find(options, &(&1.id == id)) do
      nil -> socket
      option -> reload([persist(option, fun.(option), actor)], socket)
    end
  end

  defp persist(option, attrs, actor) do
    {:ok, updated} = Ash.update(option, attrs, actor: actor)
    updated
  end

  defp reload(updated_options, socket) do
    by_id = Map.new(updated_options, &{&1.id, &1})
    options = Enum.map(socket.assigns.options, &Map.get(by_id, &1.id, &1))
    assign(socket, :options, options)
  end

  defp current_cell_state(:all, options, date), do: FulfillmentCalendar.cell_state_for_options(options, date)

  defp current_cell_state(option_id, options, date) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> :open
      option -> FulfillmentCalendar.cell_state(option, date)
    end
  end

  defp weekday_state(:all, options, weekday) do
    options
    |> Enum.map(&(weekday in &1.available_days))
    |> Enum.uniq()
    |> case do
      [true] -> :on
      [false] -> :off
      _mixed -> :mixed
    end
  end

  defp weekday_state(option_id, options, weekday) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> :on
      option -> if weekday in option.available_days, do: :on, else: :off
    end
  end

  defp scope_button_class(true),
    do: "rounded border border-primary bg-primary text-primary-content px-3 py-1 text-sm"

  defp scope_button_class(false),
    do: "rounded border border-base-content/20 px-3 py-1 text-sm hover:bg-base-content/10"

  defp admin_cell_class(_day, state, opts) do
    today? = Keyword.get(opts, :today?, false)

    base = "relative aspect-square rounded-sm focus-visible:outline-2 focus-visible:outline-offset-2"

    state_class =
      case state do
        :open ->
          "cursor-pointer hover:bg-base-content/20 focus-visible:outline-base-content"

        :weekday_off ->
          "cursor-pointer bg-error/10 hover:bg-error/20 text-base-content/70 focus-visible:outline-base-content"

        :override_off ->
          "cursor-pointer bg-error/10 hover:bg-error/20 text-base-content/70 focus-visible:outline-base-content"

        :past ->
          "cursor-not-allowed text-base-content/20 focus-visible:outline-base-content"

        :mixed ->
          "cursor-not-allowed bg-base-content/10 text-base-content/50 focus-visible:outline-base-content"
      end

    if today?, do: "#{base} #{state_class} underline", else: "#{base} #{state_class}"
  end

  defp admin_weekday_class(state) do
    base =
      "rounded-sm px-1 py-0.5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-base-content"

    state_class =
      case state do
        :on -> "cursor-pointer hover:bg-base-content/10"
        :off -> "cursor-pointer bg-error/10 hover:bg-error/20"
        :mixed -> "cursor-not-allowed bg-base-content/10 text-base-content/50"
      end

    "#{base} #{state_class}"
  end

  defp legend_swatch(state) do
    "inline-block w-3 h-3 mr-2 rounded-sm align-middle " <>
      case state do
        :closed -> "bg-error/20"
        :mixed -> "bg-base-content/20"
      end
  end
end

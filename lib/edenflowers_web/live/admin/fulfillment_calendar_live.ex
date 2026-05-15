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

  alias Edenflowers.Store.{FulfillmentCalendar, FulfillmentOption, KeyDates}

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
          <.live_component
            id="admin-fulfillment-calendar"
            field={nil}
            module={EdenflowersWeb.CalendarComponent}
            selected_date={nil}
            cell_state={fn date -> current_cell_state(@scope, @options, date) end}
            cell_class={fn day, state, opts -> admin_cell_class(day, state, opts, override?(@scope, @options, day)) end}
            cell_confirm={fn date -> key_date_close_confirm(date, current_cell_state(@scope, @options, date)) end}
            clickable_states={[:open, :weekday_off, :override_off]}
            on_click={:fulfillment_date_toggled}
            on_weekday_click={:fulfillment_weekday_toggled}
            weekday_class={fn weekday -> admin_weekday_class(weekday_state(@scope, @options, weekday)) end}
          >
            <:day_decoration :let={day}>
              <.icon
                :if={icon = KeyDates.icon_for(day)}
                name={icon}
                class="text-error absolute right-0 bottom-0 left-0 m-auto h-3 w-3 -translate-y-0.5"
              />
            </:day_decoration>
          </.live_component>
        </div>

        <aside class="text-sm md:max-w-xs md:pt-2">
          <h2 class="eyebrow text-base-content/55 mb-3">Legend</h2>
          <ul class="text-base-content/85 space-y-2 leading-snug">
            <li class="flex items-center"><span class={legend_swatch(:closed)}></span> Closed</li>
            <li class="flex items-center">
              <span class={legend_swatch(:override)}></span> Override (contradicts weekday rule)
            </li>
            <li class="flex items-center"><span class={legend_swatch(:mixed)}></span> Mixed (options disagree)</li>
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

  # Only show the override mark when scope is a single option — across all
  # options, "one option overrides, others don't" can't be summarized by a
  # single dot without lying.
  defp override?(:all, _options, _date), do: false

  defp override?(option_id, options, date) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> false
      option -> FulfillmentCalendar.override?(option, date)
    end
  end

  # Confirm message when an admin clicks a currently-open key date — they're
  # about to close a florist-relevant holiday. Returns nil for non-key dates
  # or for key dates that are already closed (re-opening is safe, no confirm).
  defp key_date_close_confirm(date, :open) do
    case KeyDates.name_for(date) do
      nil -> nil
      name -> "#{name} (#{date}) is a florist key date. Close it?"
    end
  end

  defp key_date_close_confirm(_date, _state), do: nil

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

  defp scope_button_class(true) do
    "rounded border border-primary bg-primary text-primary-content px-3.5 py-1.5 text-sm font-medium " <>
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-base-content"
  end

  defp scope_button_class(false) do
    "rounded border border-base-content/20 px-3.5 py-1.5 text-sm text-base-content/80 " <>
      "hover:border-base-content/40 hover:bg-base-content/5 hover:text-base-content " <>
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-base-content"
  end

  # Visual language: a florist's printed planner. Closed dates are crossed
  # out with a diagonal strike — the cell itself is marked as cancelled, not
  # just the digit. A muted gray background keeps closed cells visually
  # distinct from open ones. Cells whose state contradicts their weekday
  # rule (explicit overrides) carry a small sage dot in the bottom-right.
  defp admin_cell_class(_day, state, opts, override?) do
    today? = Keyword.get(opts, :today?, false)

    base =
      "relative aspect-square rounded text-sm font-medium leading-none flex items-center justify-center " <>
        "focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-base-content"

    # The strike is an absolute-positioned bar rotated 22° that spans most of
    # the cell width. Using `after:` keeps the digit clean and lets the bar
    # grow wider than the digit's footprint.
    closed_class =
      "cursor-pointer bg-base-content/10 text-base-content/65 " <>
        "after:absolute after:left-[22%] after:right-[22%] after:top-1/2 after:h-[2px] " <>
        "after:-translate-y-1/2 after:rotate-[-22deg] after:bg-error/75 after:content-[''] " <>
        "after:rounded-full hover:bg-base-content/15 hover:after:bg-error"

    state_class =
      case state do
        :open -> "cursor-pointer text-base-content hover:bg-primary/10"
        :weekday_off -> closed_class
        :override_off -> closed_class
        :past -> "cursor-not-allowed text-base-content/25"
        :mixed -> "cursor-not-allowed text-base-content/55 bg-base-content/8 ring-1 ring-inset ring-base-content/15"
      end

    today_class = if today?, do: " font-bold text-primary", else: ""

    # Top-right corner flag for explicit overrides — a small right-angled
    # triangle clipped from a positioned div. Sits over the cell like a folded
    # page corner, reading as "marked by hand" without competing with the
    # closed strike (bottom-half of the cell) or the today digit (centered).
    override_class =
      if override?,
        do:
          " before:absolute before:top-0 before:right-0 before:h-2 before:w-2 " <>
            "before:bg-primary/75 before:content-[''] before:[clip-path:polygon(100%_0,0_0,100%_100%)]",
        else: ""

    "#{base} #{state_class}#{today_class}#{override_class}"
  end

  defp admin_weekday_class(state) do
    base =
      "rounded px-1.5 py-1 text-xs font-semibold uppercase tracking-wider " <>
        "focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-base-content"

    state_class =
      case state do
        :on ->
          "cursor-pointer text-base-content/65 hover:text-base-content hover:bg-primary/10"

        :off ->
          "cursor-pointer bg-base-content/10 text-base-content/65 line-through decoration-2 decoration-error/75 " <>
            "hover:bg-base-content/15 hover:decoration-error"

        :mixed ->
          "cursor-not-allowed text-base-content/45 bg-base-content/8 ring-1 ring-inset ring-base-content/15"
      end

    "#{base} #{state_class}"
  end

  # The :closed swatch mirrors a closed cell in miniature: muted gray tile
  # with a diagonal red strike. The :mixed swatch is a plain ringed tile.
  defp legend_swatch(:closed) do
    "relative inline-block w-4 h-4 mr-2 rounded bg-base-content/10 align-middle " <>
      "before:absolute before:left-[22%] before:right-[22%] before:top-1/2 before:h-[2px] " <>
      "before:-translate-y-1/2 before:rotate-[-22deg] before:bg-error/75 before:content-[''] before:rounded-full"
  end

  defp legend_swatch(:override) do
    "relative inline-block w-4 h-4 mr-2 rounded align-middle ring-1 ring-inset ring-base-content/15 " <>
      "after:absolute after:top-0 after:right-0 after:h-2 after:w-2 " <>
      "after:bg-primary/75 after:content-[''] after:[clip-path:polygon(100%_0,0_0,100%_100%)]"
  end

  defp legend_swatch(:mixed) do
    "inline-block w-4 h-4 mr-2 rounded align-middle ring-1 ring-inset bg-base-content/8 ring-base-content/20"
  end
end

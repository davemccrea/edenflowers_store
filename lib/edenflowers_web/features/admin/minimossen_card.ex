defmodule EdenflowersWeb.Admin.MinimossenCard do
  @moduledoc """
  Minimossen's sales by Winpos product group, for the Overview and the Minimossen
  page. Switches between weeks, months and years, shows one group when its row is
  clicked, and puts a clicked bar's period in the headline. `wide` gives the page's
  full-width layout. Hidden before any report is imported, except
  when wide.
  """

  use EdenflowersWeb, {:live_component, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Minimossen

  # The group rows double as the chart's legend, so each group keeps its colour in both.
  # The colours follow the admin's own hue (--chart-* in admin.css).
  # shortcut: a 5th group and later are grey, add a validated colour if Winpos ever has that many.
  @group_colours ~w[bg-(--chart-1) bg-(--chart-2) bg-(--chart-3) bg-(--chart-4)]

  @impl true
  def update(assigns, socket) do
    socket = socket |> assign(wide: false) |> assign(assigns)

    # The parent re-renders on every order and booking; load the sales once.
    if socket.assigns[:sales] do
      {:ok, socket}
    else
      {:ok, socket |> assign(period: :week, group: nil, at: nil) |> load()}
    end
  end

  @impl true
  def handle_event("minimossen_period", %{"period" => period}, socket) when period in ~w(week month year) do
    {:noreply, socket |> assign(period: String.to_existing_atom(period), at: nil) |> load()}
  end

  # Clicking the chosen bar again goes back to the latest.
  def handle_event("minimossen_bar", %{"start" => start}, socket) do
    start = Date.from_iso8601!(start)
    {:noreply, update(socket, :at, &if(&1 == start, do: nil, else: start))}
  end

  # Clicking the shown group again shows them all.
  def handle_event("minimossen_group", %{"code" => code}, socket),
    do: {:noreply, update(socket, :group, &if(&1 == code, do: nil, else: code))}

  defp load(socket) do
    %{period: period, current_user: actor} = socket.assigns
    assign(socket, :sales, Minimossen.recent_minimossen_sales!([period: period], actor: actor))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class={(!@wide and @sales.periods == []) && "hidden"}>
      <.minimossen_widget
        :if={@sales.periods != []}
        period={@period}
        selected={@group}
        at={@at}
        groups={@sales.groups}
        periods={@sales.periods}
        locale={@locale}
        wide={@wide}
        myself={@myself}
      />
      <p :if={@wide and @sales.periods == []} class="text-base-content/75 text-sm">
        {~t"No Winpos reports imported yet."}
      </p>
    </div>
    """
  end

  attr :period, :atom, required: true, values: [:week, :month, :year]
  attr :groups, :list, required: true, doc: "the product groups, from `recent_minimossen_sales`"
  attr :periods, :list, required: true, doc: "oldest first, from `recent_minimossen_sales`"
  attr :selected, :string, required: true, doc: "the code of the only group shown, or nil for all of them"
  attr :at, :any, required: true, doc: "the start of the chosen bar's period, or nil for the latest"
  attr :locale, :any, required: true
  attr :wide, :boolean, required: true
  attr :myself, :any, required: true

  defp minimossen_widget(assigns) do
    groups =
      assigns.groups
      |> Enum.with_index()
      |> Enum.map(fn {group, index} ->
        %{group | name: group_name(group.code, group.name)} |> Map.put(:colour, group_colour(index))
      end)

    # A group or period that isn't in these reports falls back to all groups and the latest.
    selected = Enum.find(groups, &(&1.code == assigns.selected))
    chosen = Enum.find(assigns.periods, &(&1.start == assigns.at))
    shown = chosen || List.last(assigns.periods)
    total = fn amounts -> if selected, do: amounts.groups[selected.code], else: amounts.total end
    # The shown period's average can come from weeks before the chart, so it counts towards the scale too.
    highest =
      [shown.average && total.(shown.average) | Enum.map(assigns.periods, total)]
      |> Enum.reject(&is_nil/1)
      |> Enum.max(Decimal)
      |> Decimal.to_float()

    assigns =
      assign(assigns,
        groups: groups,
        selected: selected,
        listed: if(selected, do: [selected], else: groups),
        stacked: if(selected, do: [selected], else: Enum.reverse(groups)),
        chosen: chosen && chosen.start,
        shown: shown,
        shown_total: total.(shown),
        average_total: shown.average && total.(shown.average),
        average_height: shown.average && bar_height(total.(shown.average), highest),
        bars:
          Enum.map(assigns.periods, fn period ->
            %{
              start: period.start,
              groups: period.groups,
              total: total.(period),
              height: bar_height(total.(period), highest),
              heights: Map.new(period.groups, fn {code, gross} -> {code, bar_height(gross, highest)} end)
            }
          end)
      )

    ~H"""
    <.widget id="minimossen" title={~t"Minimossen"}>
      <%!-- Wide, the chart sits beside the figures so their rows don't stretch across the page. --%>
      <div class={@wide && "lg:grid-cols-[minmax(0,20rem)_minmax(0,1fr)] lg:grid lg:gap-8"}>
        <div>
          <div class="mb-3 flex gap-1" role="group" aria-label={~t"Show sales by"}>
            <button
              :for={{period, label} <- [week: ~t"Week", month: ~t"Month", year: ~t"Year"]}
              type="button"
              phx-click="minimossen_period"
              phx-target={@myself}
              phx-value-period={period}
              aria-pressed={to_string(period == @period)}
              class="btn btn-xs rounded-full font-normal shadow-none aria-pressed:btn-primary not-aria-pressed:btn-ghost pointer-coarse:btn-sm"
            >
              {label}
            </button>
          </div>

          <dl>
            <dt class="text-base-content/75 text-sm">
              {sales_heading(@period, @shown.start, @locale)}
            </dt>
            <dd id="minimossen-total" class="text-base-content text-3xl font-semibold tabular-nums tracking-tight">
              {Format.currency(@shown_total, @locale)}
            </dd>
            <dd :if={@shown.average} id="minimossen-change" class="text-base-content/75 text-sm tabular-nums">
              {~t"#{change = change(@shown_total, @average_total, @locale)} on the 8-week average"}
            </dd>
          </dl>

          <dl id="minimossen-groups" class="mt-3 space-y-1 text-sm tabular-nums">
            <div
              :for={group <- @groups}
              class={["flex items-baseline gap-3", @selected not in [nil, group] && "opacity-50"]}
            >
              <dt class="flex-1">
                <button
                  type="button"
                  phx-click="minimossen_group"
                  phx-target={@myself}
                  phx-value-code={group.code}
                  aria-pressed={to_string(@selected == group)}
                  class="text-base-content/75 flex cursor-pointer items-center gap-1.5 text-left aria-pressed:text-base-content aria-pressed:font-semibold hover:text-base-content"
                >
                  <span class={[group.colour, "h-2.5 w-2.5 shrink-0 rounded-sm"]} /> {group.name}
                </button>
              </dt>
              <dd class="font-semibold">{Format.currency(@shown.groups[group.code], @locale)}</dd>
              <dd :if={@shown.average} class="text-base-content/75 w-24 text-right">
                {change(@shown.groups[group.code], @shown.average.groups[group.code], @locale)}
              </dd>
            </div>
          </dl>
        </div>

        <figure class={["border-base-content/12 mt-4 border-t pt-3", @wide && "lg:mt-0 lg:border-t-0 lg:pt-0"]}>
          <figcaption class="text-base-content/75 mb-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs">
            <span class="text-base-content mr-auto">
              {case @period do
                :week -> ~t"By week"
                :month -> ~t"By month"
                :year -> ~t"By year"
              end}
            </span>
            <span :if={@shown.average} class="flex items-center gap-1.5" aria-hidden="true">
              <span class="border-base-content/40 w-4 border-t border-dashed" /> {~t"8-week average"}
            </span>
          </figcaption>
          <div
            id="minimossen-bars"
            class={["border-base-content/12 relative flex h-24 items-end gap-1 border-b", @wide && "lg:h-56"]}
          >
            <%!-- forms.css stops clicks on a loading button, which would drop the hover and blink the
          tooltip. Clicking a bar twice just toggles it back, so it stays clickable. --%>
            <button
              :for={{bar, index} <- Enum.with_index(@bars)}
              type="button"
              phx-click="minimossen_bar"
              phx-target={@myself}
              phx-value-start={bar.start}
              aria-pressed={to_string(@chosen == bar.start)}
              aria-label={"#{period_label(@period, bar.start, @locale)}: #{Format.currency(bar.total, @locale)}"}
              class="group/bar relative flex h-full flex-1 cursor-pointer flex-col justify-end gap-0.5 rounded-t-sm hover:bg-base-content/6 phx-click-loading:pointer-events-auto!"
            >
              <span
                :for={group <- @stacked}
                class={[group.colour, "block first:rounded-t-sm", @chosen not in [nil, bar.start] && "opacity-40"]}
                style={"height: #{bar.heights[group.code]}%"}
              />
              <%!-- Bars in the left half open their tooltip rightwards, so it never leaves the card. --%>
              <span
                aria-hidden="true"
                style={"bottom: calc(#{bar.height}% + 0.375rem)"}
                class={["bg-base-100 border-base-content/12 pointer-events-none absolute z-10 hidden text-left", "whitespace-nowrap rounded-md border px-2.5 py-1.5 text-xs shadow-sm", "group-focus-visible/bar:block group-hover/bar:block", if(index < length(@bars) / 2, do: "left-0", else: "right-0")]}
              >
                <span class="text-base-content block font-semibold">{period_label(@period, bar.start, @locale)}</span>
                <span :for={group <- @listed} class="flex items-center gap-1.5">
                  <span class={[group.colour, "h-2 w-2 shrink-0 rounded-sm"]} />
                  <span class="text-base-content/75 mr-auto pr-3">{group.name}</span>
                  <span class="text-base-content tabular-nums">{Format.currency(bar.groups[group.code], @locale)}</span>
                </span>
                <span
                  :if={!@selected}
                  class="border-base-content/12 mt-1 flex justify-between gap-3 border-t pt-1 font-semibold"
                >
                  <span>{~t"Total"}</span>
                  <span class="tabular-nums">{Format.currency(bar.total, @locale)}</span>
                </span>
              </span>
            </button>
            <div
              :if={@shown.average}
              class="border-base-content/40 pointer-events-none absolute inset-x-0 border-t border-dashed"
              style={"bottom: #{@average_height}%"}
            />
          </div>
          <div
            class={["text-base-content/75 mt-1 flex justify-between text-xs tabular-nums", @wide && "lg:hidden"]}
            aria-hidden="true"
          >
            <span>{period_label(@period, hd(@periods).start, @locale)}</span>
            <span>{period_label(@period, List.last(@periods).start, @locale)}</span>
          </div>
          <%!-- Wide enough on a large screen to name every bar, matching the bars' own gap. --%>
          <div
            :if={@wide}
            class="text-base-content/75 mt-1 hidden gap-1 text-xs tabular-nums lg:flex"
            aria-hidden="true"
          >
            <span :for={bar <- @bars} class="flex-1 truncate text-center">
              {bar_label(@period, bar.start, @locale)}
            </span>
          </div>
        </figure>
      </div>
    </.widget>
    """
  end

  defp sales_heading(:week, start, _locale), do: ~t"Sales in week #{week = week_number(start)}"

  defp sales_heading(:month, start, locale),
    do: ~t"Sales in #{month = Localize.Date.to_string!(start, locale: locale, format: "LLLL y")}"

  defp sales_heading(:year, start, _locale), do: ~t"Sales in #{year = start.year}"

  # Under the chart's ends, e.g. "Week 34", "Nov 2025", "2024".
  defp period_label(:week, start, _locale), do: ~t"Week #{week = week_number(start)}"
  defp period_label(:month, start, locale), do: Localize.Date.to_string!(start, locale: locale, format: "LLL y")
  defp period_label(:year, start, _locale), do: to_string(start.year)

  # Under each bar of the wide chart, e.g. "v. 34" in Swedish.
  defp bar_label(:week, start, _locale), do: ~t"Wk #{week = week_number(start)}"
  defp bar_label(period, start, locale), do: period_label(period, start, locale)

  defp group_colour(index), do: Enum.at(@group_colours, index, "bg-base-content/30")

  # Winpos names the groups in Finnish, some with its own numbering.
  defp group_name("3", _winpos_name), do: ~t"Flowers"
  defp group_name("6", _winpos_name), do: ~t"Pots"
  defp group_name("7", _winpos_name), do: ~t"Toys"
  defp group_name("66", _winpos_name), do: ~t"Books and magazines"
  defp group_name(_code, winpos_name), do: winpos_name

  # How much more or less than the usual week, signed, e.g. "+37,00 €".
  defp change(now, usual, locale) do
    difference = Decimal.sub(now, usual)

    if Decimal.positive?(difference),
      do: "+" <> Format.currency(difference, locale),
      else: Format.currency(difference, locale)
  end

  defp bar_height(_amount, highest) when highest == 0, do: 0
  defp bar_height(amount, highest), do: Float.round(Decimal.to_float(amount) / highest * 100, 1)

  defp week_number(date) do
    {_year, week} = :calendar.iso_week_number(Date.to_erl(date))
    week
  end
end

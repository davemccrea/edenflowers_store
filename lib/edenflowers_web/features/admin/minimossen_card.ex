defmodule EdenflowersWeb.Admin.MinimossenCard do
  @moduledoc """
  Minimossen's sales by Winpos product group, for the Overview and the Minimossen
  page. Switches between weeks, months and years, shows one group when its row is
  clicked, and puts a clicked bar's period in the headline. `wide` gives the page's
  full-width layout with a scale, a table and this year's months, and keeps the choices
  in the page's URL, which passes them back in. Hidden before any report is
  imported, except when wide.
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
    socket =
      socket
      |> assign_new(:wide, fn -> false end)
      |> assign_new(:period, fn -> :week end)
      |> assign_new(:group, fn -> nil end)
      |> assign_new(:at, fn -> nil end)
      |> assign(assigns)

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("minimossen_period", %{"period" => period}, socket) when period in ~w(week month year),
    do: choose(socket, period: String.to_existing_atom(period), at: nil)

  # Clicking the chosen bar again goes back to the latest.
  def handle_event("minimossen_bar", %{"start" => start}, socket) do
    start = Date.from_iso8601!(start)
    choose(socket, at: if(socket.assigns.at == start, do: nil, else: start))
  end

  # Clicking the shown group again shows them all.
  def handle_event("minimossen_group", %{"code" => code}, socket),
    do: choose(socket, group: if(socket.assigns.group == code, do: nil, else: code))

  # Wide, the page's URL holds the choices, so the back button and a bookmark keep them.
  defp choose(socket, changes) do
    if socket.assigns.wide do
      choices = socket.assigns |> Map.take([:period, :group, :at]) |> Map.merge(Map.new(changes))
      {:noreply, push_patch(socket, to: path(choices))}
    else
      {:noreply, socket |> assign(changes) |> load()}
    end
  end

  @doc "The Minimossen page showing these choices; the defaults stay out of the URL."
  def path(choices) do
    query = for {key, value} <- choices, value not in [nil, :week], do: {key, to_string(value)}
    ~p"/admin/minimossen?#{query}"
  end

  # The Overview re-renders on every order and booking, so only a new period reloads.
  defp load(%{assigns: %{period: period, loaded: period}} = socket), do: socket

  defp load(socket) do
    %{period: period, wide: wide, current_user: actor} = socket.assigns
    # The page shows this year's months, January on; years compare across them all.
    arguments = [period: period, count: 12, this_year: wide and period == :month]
    assign(socket, sales: Minimossen.recent_minimossen_sales!(arguments, actor: actor), loaded: period)
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
    total = fn amounts -> amounts && if(selected, do: amounts.groups[selected.code], else: amounts.total) end
    # Weeks compare their rows with the usual week, months and years with last year.
    compare = shown.average || shown.last_year

    bars =
      Enum.map(assigns.periods, fn period ->
        %{
          start: period.start,
          groups: period.groups,
          partial?: period.partial?,
          total: total.(period),
          average: total.(period.average),
          last_year: total.(period.last_year)
        }
      end)

    # Last year's marks count too, so none of them sticks out above the chart.
    highest =
      bars
      |> Enum.flat_map(&[&1.total, &1.last_year])
      |> Enum.reject(&is_nil/1)
      |> Enum.max(Decimal)
      |> Decimal.to_float()

    {top, ticks} = scale(highest)

    assigns =
      assign(assigns,
        groups: groups,
        selected: selected,
        listed: if(selected, do: [selected], else: groups),
        stacked: if(selected, do: [selected], else: Enum.reverse(groups)),
        chosen: chosen && chosen.start,
        shown: shown,
        shown_total: total.(shown),
        average_total: total.(shown.average),
        last_year_total: total.(shown.last_year),
        compare: compare,
        top: top,
        ticks: ticks,
        bars: bars,
        label_rows: axis_labels(assigns.period, Enum.map(bars, & &1.start), assigns.locale),
        any_last_year?: Enum.any?(bars, & &1.last_year)
      )

    ~H"""
    <.widget id="minimossen" title={!@wide && ~t"Minimossen"} navigate={!@wide && ~p"/admin/minimossen"}>
      <%!-- Wide, the page's header holds the period switch. --%>
      <div :if={!@wide} class="mb-3 flex gap-1" role="group" aria-label={~t"Show sales by"}>
        <button
          :for={{period, label} <- period_choices()}
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

      <%!-- Wide, the headline and the groups share one strip above the chart. --%>
      <div class={@wide && "lg:flex lg:items-end lg:justify-between lg:gap-10"}>
        <dl>
          <dt class="text-base-content/75 text-sm">
            {sales_heading(@period, @shown.start, @locale)}
            <span :if={@shown.partial?} class="badge badge-sm badge-ghost ml-1 align-middle">{partial()}</span>
          </dt>
          <dd id="minimossen-total" class="text-base-content text-3xl font-semibold tabular-nums tracking-tight">
            {Format.currency(@shown_total, @locale)}
          </dd>
          <dd :if={@shown.average} id="minimossen-change" class="text-base-content/75 text-sm tabular-nums">
            {~t"#{change = full_change(@shown_total, @average_total, @locale)} on the 8-week average"}
          </dd>
          <dd :if={@shown.last_year} id="minimossen-last-year" class="text-base-content/75 text-sm tabular-nums">
            {last_year_change(@period, full_change(@shown_total, @last_year_total, @locale), @shown.last_year, @locale)}
          </dd>
        </dl>

        <dl
          id="minimossen-groups"
          class={["mt-3 space-y-1 text-sm tabular-nums", @wide && "lg:mt-0 lg:flex lg:gap-8 lg:space-y-0"]}
        >
          <div
            :for={group <- @groups}
            class={["flex items-baseline gap-3", @wide && "lg:flex-col lg:items-start lg:gap-0.5", @selected not in [nil, group] && "opacity-50"]}
          >
            <dt class="flex-1">
              <button
                type="button"
                phx-click="minimossen_group"
                phx-target={@myself}
                phx-value-code={group.code}
                aria-pressed={to_string(@selected == group)}
                class="text-base-content/75 flex cursor-pointer items-center gap-1.5 whitespace-nowrap text-left aria-pressed:text-base-content aria-pressed:font-semibold hover:text-base-content"
              >
                <span class={[group.colour, "h-2.5 w-2.5 shrink-0 rounded-sm"]} /> {group.name}
              </button>
            </dt>
            <dd class="font-semibold">{Format.currency(@shown.groups[group.code], @locale)}</dd>
            <dd :if={@compare} class={["text-base-content/75 w-24 text-right", @wide && "lg:w-auto lg:text-left"]}>
              {percent_change(@shown.groups[group.code], @compare.groups[group.code], @locale)}
            </dd>
          </div>
        </dl>
      </div>

      <figure class={["border-base-content/12 mt-4 border-t pt-3", @wide && "lg:mt-6 lg:pt-6"]}>
        <div
          id="minimossen-bars"
          class={["border-base-content/12 relative flex h-24 items-end justify-center gap-1 border-b", @wide && "lg:ml-14 lg:h-80"]}
        >
          <%!-- A scale on the page, where there's room for its amounts. --%>
          <div
            :for={tick <- @ticks}
            :if={@wide}
            aria-hidden="true"
            class="border-base-content/8 pointer-events-none absolute inset-x-0 hidden border-t lg:block"
            style={"bottom: #{bar_height(tick, @top)}%"}
          >
            <span class="text-base-content/60 absolute right-full -translate-y-1/2 pr-2 text-xs tabular-nums">
              {Format.storefront_price(Decimal.from_float(tick), @locale)}
            </span>
          </div>
          <%!-- forms.css stops clicks on a loading button, which would drop the hover and blink the
          tooltip. Clicking a bar twice just toggles it back, so it stays clickable. --%>
          <button
            :for={{bar, index} <- Enum.with_index(@bars)}
            type="button"
            phx-click="minimossen_bar"
            phx-target={@myself}
            phx-value-start={bar.start}
            aria-pressed={to_string(@chosen == bar.start)}
            aria-label={"#{bar_name(@period, bar, @locale)}: #{Format.currency(bar.total, @locale)}"}
            class="group/bar max-w-24 relative flex h-full flex-1 cursor-pointer flex-col justify-end gap-0.5 rounded-t-sm hover:bg-base-content/6 phx-click-loading:pointer-events-auto!"
          >
            <span
              :for={group <- @stacked}
              class={[group.colour, "block first:rounded-t-sm", @chosen not in [nil, bar.start] && "opacity-40"]}
              style={"height: #{bar_height(bar.groups[group.code], @top)}%"}
            />
            <%!-- Hatched while partial, so a month or year under way doesn't read as a fall. --%>
            <span
              :if={bar.partial?}
              aria-hidden="true"
              class="bg-[repeating-linear-gradient(135deg,transparent_0_4px,var(--color-base-100)_4px_6px)] pointer-events-none absolute inset-x-0 bottom-0 opacity-70"
              style={"height: #{bar_height(bar.total, @top)}%"}
            />
            <%!-- The same period a year before, like for like while under way. --%>
            <span
              :if={bar.last_year}
              aria-hidden="true"
              class="border-base-content/70 pointer-events-none absolute inset-x-0 border-t-2 border-dashed"
              style={"bottom: #{bar_height(bar.last_year, @top)}%"}
            />
            <%!-- Bars in the left half open their tooltip rightwards, so it never leaves the card. --%>
            <span
              aria-hidden="true"
              style={"bottom: calc(#{bar_height(bar.total, @top)}% + 0.375rem)"}
              class={["bg-base-100 border-base-content/12 pointer-events-none absolute z-10 hidden text-left", "whitespace-nowrap rounded-md border px-2.5 py-1.5 text-xs shadow-sm", "group-focus-visible/bar:block group-hover/bar:block", if(index < length(@bars) / 2, do: "left-0", else: "right-0")]}
            >
              <span class="text-base-content block font-semibold">{bar_name(@period, bar, @locale)}</span>
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
              <span :if={bar.last_year} class="text-base-content/75 flex items-center justify-between gap-3">
                <span class="flex items-center gap-1.5">
                  <span class="border-base-content/70 w-2 border-t-2 border-dashed" />{~t"A year before"}
                </span>
                <span class="tabular-nums">{Format.currency(bar.last_year, @locale)}</span>
              </span>
            </span>
          </button>
        </div>
        <div
          class={["text-base-content/75 mt-1 flex justify-between text-xs tabular-nums", @wide && "lg:hidden"]}
          aria-hidden="true"
        >
          <span>{period_label(@period, hd(@periods).start, @locale)}</span>
          <span>{period_label(@period, List.last(@periods).start, @locale)}</span>
        </div>
        <%!-- On a large screen, months under the weeks and years under the months, matching the bars' gap. --%>
        <div
          :for={labels <- @label_rows}
          :if={@wide}
          class="text-base-content/75 mt-1 ml-14 hidden justify-center gap-1 text-xs tabular-nums lg:flex"
          aria-hidden="true"
        >
          <span
            :for={label <- labels}
            class="max-w-24 min-w-0 flex-1 whitespace-nowrap text-center"
          >
            {label}
          </span>
        </div>
        <figcaption :if={@any_last_year?} class="text-base-content/75 mt-2 flex items-center gap-1.5 text-xs">
          <span class="border-base-content/70 w-3 border-t-2 border-dashed" aria-hidden="true" />
          {last_year_legend(@period)}
        </figcaption>
      </figure>

      <div :if={@wide} class="mt-8 hidden overflow-x-auto lg:block">
        <table id="minimossen-table" class="w-full text-sm tabular-nums">
          <thead class="text-base-content/75 border-base-content/12 whitespace-nowrap border-b text-left text-xs">
            <tr>
              <th scope="col" class="pb-2 font-semibold">{period_heading(@period)}</th>
              <th :for={group <- @listed} scope="col" class="pb-2 pl-4 text-right font-semibold">{group.name}</th>
              <th :if={!@selected} scope="col" class="pb-2 pl-4 text-right font-semibold">{~t"Total"}</th>
              <th :if={@period == :week} scope="col" class="pb-2 pl-4 text-right font-semibold">
                {~t"vs. 8-week average"}
              </th>
              <th :if={@any_last_year?} scope="col" class="pb-2 pl-4 text-right font-semibold">
                {~t"vs. a year before"}
              </th>
            </tr>
          </thead>
          <tbody class="divide-base-content/12 divide-y">
            <tr
              :for={bar <- Enum.reverse(@bars)}
              class={[@chosen == bar.start && "bg-base-content/6", "hover:bg-base-content/4"]}
            >
              <th scope="row" class="py-2 text-left font-normal">
                <button
                  type="button"
                  phx-click="minimossen_bar"
                  phx-target={@myself}
                  phx-value-start={bar.start}
                  aria-pressed={to_string(@chosen == bar.start)}
                  class="cursor-pointer text-left aria-pressed:font-semibold hover:underline"
                >
                  {period_label(@period, bar.start, @locale)}
                </button>
                <span :if={bar.partial?} class="text-base-content/60 ml-1 text-xs">{partial()}</span>
              </th>
              <td :for={group <- @listed} class="py-2 pl-4 text-right">
                {Format.currency(bar.groups[group.code], @locale)}
              </td>
              <td :if={!@selected} class="py-2 pl-4 text-right font-semibold">{Format.currency(bar.total, @locale)}</td>
              <td :if={@period == :week} class="text-base-content/75 py-2 pl-4 text-right">
                {bar.average && full_change(bar.total, bar.average, @locale)}
              </td>
              <td :if={@any_last_year?} class="text-base-content/75 py-2 pl-4 text-right">
                {bar.last_year && full_change(bar.total, bar.last_year, @locale)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </.widget>
    """
  end

  def period_choices, do: [week: ~t"Week", month: ~t"Month", year: ~t"Year"]

  defp sales_heading(:week, start, _locale), do: ~t"Sales in week #{week = week_number(start)}"

  defp sales_heading(:month, start, locale),
    do: ~t"Sales in #{month = Localize.Date.to_string!(start, locale: locale, format: "LLLL y")}"

  defp sales_heading(:year, start, _locale), do: ~t"Sales in #{year = start.year}"

  defp period_heading(:week), do: ~t"Week"
  defp period_heading(:month), do: ~t"Month"
  defp period_heading(:year), do: ~t"Year"

  defp partial do
    gettext_comment(
      "Beside a month or year whose sales aren't all in: still under way, or begun before the first Winpos report."
    )

    ~t"partial"
  end

  # Under the chart's ends, e.g. "Week 34", "Nov 2025", "2024".
  defp period_label(:week, start, _locale), do: ~t"Week #{week = week_number(start)}"
  defp period_label(:month, start, locale), do: Localize.Date.to_string!(start, locale: locale, format: "LLL y")
  defp period_label(:year, start, _locale), do: to_string(start.year)

  defp bar_name(period, %{partial?: true} = bar, locale), do: "#{period_label(period, bar.start, locale)}, #{partial()}"
  defp bar_name(period, bar, locale), do: period_label(period, bar.start, locale)

  # The rows of labels under the wide chart's bars, one label per bar, nil where it
  # would repeat the one before: years; months over years; or week numbers over the
  # months their Thursdays fall in, as sales count them, each year named where it starts.
  defp axis_labels(:year, starts, _locale), do: [Enum.map(starts, &to_string(&1.year))]

  defp axis_labels(:month, starts, locale),
    do: [Enum.map(starts, &Format.short_month(&1, locale)), new_years(starts)]

  defp axis_labels(:week, starts, locale) do
    thursdays = Enum.map(starts, &Date.add(&1, 3))

    months =
      for {previous, date} <- Enum.zip([nil | thursdays], thursdays), year <- [new_year(previous, date)] do
        cond do
          year -> "#{Format.short_month(date, locale)} #{year}"
          previous.month != date.month -> Format.short_month(date, locale)
          true -> nil
        end
      end

    [Enum.map(starts, &week_number/1), months]
  end

  defp new_years(dates), do: Enum.zip_with([nil | dates], dates, &new_year/2)

  defp new_year(previous, date), do: if(previous == nil or previous.year != date.year, do: date.year)

  defp last_year_change(:week, change, _last_year, _locale), do: ~t"#{change} on the same week last year"

  defp last_year_change(:month, change, last_year, locale) do
    month = Localize.Date.to_string!(last_year.start, locale: locale, format: "LLLL y")

    if last_year.partial?,
      do: ~t"#{change} on the same weeks of #{month}",
      else: ~t"#{change} on #{month}"
  end

  defp last_year_change(:year, change, last_year, _locale) do
    year = last_year.start.year
    if last_year.partial?, do: ~t"#{change} on the same weeks of #{year}", else: ~t"#{change} on #{year}"
  end

  defp last_year_legend(:week), do: ~t"The same week a year before"
  defp last_year_legend(_period), do: ~t"The same weeks a year before"

  defp group_colour(index), do: Enum.at(@group_colours, index, "bg-base-content/30")

  # Winpos names the groups in Finnish, some with its own numbering.
  defp group_name("3", _winpos_name), do: ~t"Flowers"
  defp group_name("6", _winpos_name), do: ~t"Pots"
  defp group_name("7", _winpos_name), do: ~t"Toys"
  defp group_name("66", _winpos_name), do: ~t"Books and magazines"
  defp group_name(_code, winpos_name), do: winpos_name

  # How much more or less than the usual, e.g. "+52 % (+192,50 €)", or just the amount
  # when there was nothing to compare with.
  defp full_change(now, usual, locale) do
    case percent(now, usual, locale) do
      nil -> change(now, usual, locale)
      percent -> "#{percent} (#{change(now, usual, locale)})"
    end
  end

  # The group rows have room for one figure; the table gives the amounts.
  defp percent_change(now, usual, locale), do: percent(now, usual, locale) || change(now, usual, locale)

  defp change(now, usual, locale), do: signed(Decimal.sub(now, usual), &Format.currency(&1, locale))

  defp percent(now, usual, locale) do
    if Decimal.positive?(usual) do
      rate = now |> Decimal.div(usual) |> Decimal.sub(1)
      signed(rate, &Localize.Number.to_string!(&1, locale: locale, format: :percent, fractional_digits: 0))
    end
  end

  defp signed(amount, format) do
    if Decimal.positive?(amount), do: "+" <> format.(amount), else: format.(amount)
  end

  # A scale of up to 3 round steps, and the amount at its top.
  defp scale(highest) when highest == 0, do: {0.0, []}

  defp scale(highest) do
    rough = highest / 3
    magnitude = :math.pow(10, Float.floor(:math.log10(rough)))
    step = Enum.find([1, 2, 2.5, 5, 10], &(&1 * magnitude >= rough)) * magnitude
    steps = ceil(highest / step)
    {steps * step, for(n <- 1..steps, do: Float.round(n * step, 2))}
  end

  defp bar_height(_amount, top) when top == 0, do: 0
  defp bar_height(%Decimal{} = amount, top), do: bar_height(Decimal.to_float(amount), top)
  defp bar_height(amount, top), do: Float.round(amount / top * 100, 1)

  defp week_number(date) do
    {_year, week} = :calendar.iso_week_number(Date.to_erl(date))
    week
  end
end

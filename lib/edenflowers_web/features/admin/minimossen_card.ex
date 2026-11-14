defmodule EdenflowersWeb.Admin.MinimossenCard do
  @moduledoc """
  Minimossen's sales by Winpos product group. The live component is the Overview's
  card, with its own week or month switch, hidden before any report is imported.
  `sales/1` draws the sales for it and, `wide`, for the Minimossen page, which keeps its
  choices in the URL and adds a scale, group chips and a table.
  """

  use EdenflowersWeb, {:live_component, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Minimossen

  # The legend's colours, one per group in the rows, chips and bars alike.
  # The colours follow the admin's own hue (--chart-* in admin.css).
  # shortcut: a 5th group and later are grey, add a validated colour if Winpos ever has that many.
  @group_colours ~w[bg-(--chart-1) bg-(--chart-2) bg-(--chart-3) bg-(--chart-4)]

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign_new(:period, fn -> :week end) |> assign(assigns) |> load()}
  end

  @impl true
  def handle_event("minimossen_period", %{"period" => period}, socket) when period in ~w(week month),
    do: {:noreply, socket |> assign(period: String.to_existing_atom(period)) |> load()}

  # The Overview re-renders on every order and booking, so only a new period reloads.
  defp load(%{assigns: %{period: period, loaded: period}} = socket), do: socket

  defp load(socket) do
    sales = Minimossen.recent_minimossen_sales!([period: socket.assigns.period], actor: socket.assigns.current_user)
    assign(socket, sales: sales, loaded: socket.assigns.period)
  end

  @doc "The Minimossen page showing this period and group; the defaults stay out of the URL."
  def page_path(period, group) do
    query = for {key, value} <- [period: period, group: group], value not in [nil, :week], do: {key, to_string(value)}
    ~p"/admin/minimossen?#{query}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class={@sales.periods == [] && "hidden"}>
      <.widget :if={@sales.periods != []} id="minimossen" title={~t"Minimossen"} navigate={~p"/admin/minimossen"}>
        <div class="mb-3 flex gap-1" role="group" aria-label={~t"Show sales by"}>
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
        <.sales period={@period} sales={@sales} locale={@locale} />
      </.widget>
    </div>
    """
  end

  attr :period, :atom, required: true, values: [:week, :month]
  attr :sales, :map, required: true, doc: "from `recent_minimossen_sales`, with at least one period"
  attr :group, :string, default: nil, doc: "the code of the only group shown, or nil for all of them"
  attr :locale, :any, required: true
  attr :wide, :boolean, default: false, doc: "the page's layout, with group chips, a scale and a table"

  def sales(assigns) do
    groups =
      assigns.sales.groups
      |> Enum.with_index()
      |> Enum.map(fn {group, index} ->
        %{group | name: group_name(group.code, group.name)} |> Map.put(:colour, group_colour(index))
      end)

    # A group that isn't in these reports falls back to all of them.
    selected = Enum.find(groups, &(&1.code == assigns.group))
    total = fn amounts -> amounts && if(selected, do: amounts.groups[selected.code], else: amounts.total) end
    latest = List.last(assigns.sales.periods)

    bars =
      Enum.map(assigns.sales.periods, fn period ->
        %{
          start: period.start,
          groups: period.groups,
          partial?: period.partial?,
          total: total.(period),
          last_year: total.(period.last_year)
        }
      end)

    # All groups set the scale, whichever is shown, so switching group keeps the bars
    # comparable. Last year's marks count too, so none of them sticks out above the chart.
    highest =
      assigns.sales.periods
      |> Enum.flat_map(&[&1.total, &1.last_year && &1.last_year.total])
      |> Enum.reject(&is_nil/1)
      |> Enum.max(Decimal)
      |> Decimal.to_float()

    {top, ticks} = scale(highest)

    assigns =
      assign(assigns,
        groups: groups,
        selected: selected,
        listed: if(selected, do: [selected], else: groups),
        # Top to bottom. A chosen group sits on the axis with the rest in grey above it,
        # so a small group still shows its share on the scale all groups share.
        stacked: if(selected, do: Enum.reverse(groups -- [selected]) ++ [selected], else: Enum.reverse(groups)),
        latest: latest,
        latest_total: total.(latest),
        average_total: total.(latest.average),
        last_year_total: total.(latest.last_year),
        # Weeks compare their rows with the usual week, months with last year.
        compare: latest.average || latest.last_year,
        top: top,
        ticks: ticks,
        bars: bars,
        label_rows: axis_labels(assigns.period, Enum.map(bars, & &1.start), assigns.locale),
        any_last_year?: Enum.any?(bars, & &1.last_year)
      )

    ~H"""
    <div class={@wide && "lg:flex lg:items-end lg:justify-between lg:gap-10"}>
      <div>
        <dl>
          <dt class="text-base-content/75 text-sm">
            {@selected && "#{@selected.name} · "}{heading(@period, @latest.start, @locale)}
            <span :if={@latest.partial?} class="badge badge-sm badge-ghost ml-1 align-middle">{partial()}</span>
          </dt>
          <dd id="minimossen-total" class="text-base-content text-3xl font-semibold tabular-nums tracking-tight">
            {Format.currency(@latest_total, @locale)}
          </dd>
        </dl>
        <%!-- What the latest is compared with, so a percentage on a small amount reads for what it is. --%>
        <table :if={@latest.average || @latest.last_year} class="mt-2 text-sm tabular-nums">
          <tbody>
            <tr :if={@latest.average} id="minimossen-change">
              <th scope="row" class="text-base-content/75 pr-6 text-left font-normal">{~t"8-week average"}</th>
              <td class="text-base-content/75 pr-6 text-right">{Format.currency(@average_total, @locale)}</td>
              <td class="text-right"><.change now={@latest_total} usual={@average_total} locale={@locale} /></td>
            </tr>
            <tr :if={@latest.last_year} id="minimossen-last-year">
              <th scope="row" class="text-base-content/75 pr-6 text-left font-normal">
                {last_year_label(@period, @latest.last_year, @locale)}
              </th>
              <td class="text-base-content/75 pr-6 text-right">{Format.currency(@last_year_total, @locale)}</td>
              <td class="text-right"><.change now={@latest_total} usual={@last_year_total} locale={@locale} /></td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- The page's legend is also its group filter; the table gives each group's amounts. --%>
      <nav :if={@wide} id="minimossen-groups" class="mt-4 flex flex-wrap gap-1 lg:mt-0" aria-label={~t"Show group"}>
        <.link
          :for={{group, label} <- [{nil, ~t"All groups"} | Enum.map(@groups, &{&1, &1.name})]}
          patch={page_path(@period, group && group.code)}
          aria-current={@selected == group && "page"}
          class="btn btn-sm rounded-full font-normal shadow-none aria-[current=page]:btn-primary not-aria-[current=page]:btn-ghost"
        >
          <span :if={group} class={[group.colour, "h-2.5 w-2.5 shrink-0 rounded-sm"]} /> {label}
        </.link>
      </nav>

      <dl :if={!@wide} id="minimossen-groups" class="mt-3 space-y-1 text-sm tabular-nums">
        <div :for={group <- @groups} class="flex items-baseline gap-3">
          <dt class="text-base-content/75 flex flex-1 items-center gap-1.5">
            <span class={[group.colour, "h-2.5 w-2.5 shrink-0 rounded-sm"]} /> {group.name}
          </dt>
          <dd class="font-semibold">{Format.currency(@latest.groups[group.code], @locale)}</dd>
          <dd :if={@compare} class="w-16 text-right">
            <.change now={@latest.groups[group.code]} usual={@compare.groups[group.code]} locale={@locale} />
          </dd>
        </div>
      </dl>
    </div>

    <%!-- The page's table carries the figures, so its chart is only seen. --%>
    <figure class={["border-base-content/12 mt-4 border-t pt-3", @wide && "lg:mt-6 lg:pt-6"]} aria-hidden={@wide && "true"}>
      <div
        id="minimossen-bars"
        class={["border-base-content/12 relative flex h-24 items-end justify-center gap-2 border-b", @wide && "lg:ml-14 lg:h-80 lg:gap-3"]}
      >
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
        <div
          :for={{bar, index} <- Enum.with_index(@bars)}
          role="img"
          aria-label={"#{bar_name(@period, bar, @locale)}: #{Format.currency(bar.total, @locale)}"}
          class="group/bar max-w-24 relative flex h-full flex-1 flex-col justify-end gap-0.5 rounded-t-sm hover:bg-base-content/6"
        >
          <%!-- The same period a year before, like for like while under way: an outline behind
          the bar and a little wider, so its sides still show when this year is higher. --%>
          <span
            :if={bar.last_year}
            class="border-base-content/40 bg-base-content/4 pointer-events-none absolute -inset-x-1 bottom-0 rounded-t-md border border-b-0 border-dashed"
            style={"height: #{bar_height(bar.last_year, @top)}%"}
          />
          <%!-- Relative, so the segments paint over the outline. --%>
          <span
            :for={group <- @stacked}
            class={["relative block first:rounded-t-sm", if(@selected in [nil, group], do: group.colour, else: "bg-base-content/10")]}
            style={"height: #{bar_height(bar.groups[group.code], @top)}%"}
          />
          <%!-- Hatched while partial, so a month under way doesn't read as a fall. --%>
          <span
            :if={bar.partial?}
            class="bg-[repeating-linear-gradient(135deg,transparent_0_4px,var(--color-base-100)_4px_6px)] pointer-events-none absolute inset-x-0 bottom-0 opacity-70"
            style={"height: #{bar_height(bar.total, @top)}%"}
          />
          <%!-- Bars in the left half open their tooltip rightwards, so it never leaves the card. --%>
          <span
            aria-hidden="true"
            style={"bottom: calc(#{bar_height(bar.total, @top)}% + 0.375rem)"}
            class={["bg-base-100 border-base-content/12 pointer-events-none absolute z-10 hidden text-left", "whitespace-nowrap rounded-md border px-2.5 py-1.5 text-xs shadow-sm", "group-hover/bar:block", if(index < length(@bars) / 2, do: "left-0", else: "right-0")]}
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
                <span class="border-base-content/40 h-2 w-2.5 rounded-t-sm border border-b-0 border-dashed" />{~t"A year before"}
              </span>
              <span class="tabular-nums">{Format.currency(bar.last_year, @locale)}</span>
            </span>
          </span>
        </div>
      </div>
      <div
        class={["text-base-content/75 mt-1 flex justify-between text-xs tabular-nums", @wide && "lg:hidden"]}
        aria-hidden="true"
      >
        <span>{period_label(@period, hd(@bars).start, @locale)}</span>
        <span>{period_label(@period, @latest.start, @locale)}</span>
      </div>
      <%!-- On a large screen, a label under each bar, matching the bars' gap. --%>
      <div
        :for={labels <- @label_rows}
        :if={@wide}
        class="text-base-content/75 mt-1 ml-14 hidden justify-center gap-3 text-xs tabular-nums lg:flex"
        aria-hidden="true"
      >
        <span :for={label <- labels} class="max-w-24 min-w-0 flex-1 whitespace-nowrap text-center">{label}</span>
      </div>
      <figcaption :if={@any_last_year?} class="text-base-content/75 mt-2 flex items-center gap-1.5 text-xs">
        <span
          class="border-base-content/40 bg-base-content/4 h-2.5 w-3 rounded-t-sm border border-b-0 border-dashed"
          aria-hidden="true"
        />
        {last_year_legend(@period)}
      </figcaption>
    </figure>

    <div :if={@wide} class="mt-8 overflow-x-auto">
      <%!-- Fixed columns, so each amount gets the same width whatever its group's name. --%>
      <table id="minimossen-table" class="min-w-[40rem] w-full table-fixed text-sm tabular-nums">
        <thead class="text-base-content/60 text-xs">
          <tr class="border-base-content/12 border-b">
            <th scope="col" class="w-36 pb-2 text-left font-medium">{period_heading(@period)}</th>
            <th :for={group <- @listed} scope="col" class="pb-2 pl-4 text-right font-medium">
              <span class="inline-flex max-w-full items-center gap-1.5" title={group.name}>
                <span class={[group.colour, "h-2 w-2 shrink-0 rounded-sm"]} />
                <span class="truncate">{group.name}</span>
              </span>
            </th>
            <th :if={!@selected} scope="col" class="pb-2 pl-4 text-right font-medium">{~t"Total"}</th>
            <th :if={@any_last_year?} scope="col" class="pb-2 pl-4 text-right font-medium">
              {~t"vs. a year before"}
            </th>
          </tr>
        </thead>
        <tbody class="divide-base-content/8 divide-y">
          <tr :for={bar <- Enum.reverse(@bars)} class="hover:bg-base-content/4">
            <th scope="row" class="whitespace-nowrap py-1.5 text-left font-normal">
              {period_label(@period, bar.start, @locale)}
              <span :if={bar.partial?} class="badge badge-xs badge-ghost ml-1">{partial()}</span>
            </th>
            <td :for={group <- @listed} class="text-base-content/75 py-1.5 pl-4 text-right">
              {Format.currency(bar.groups[group.code], @locale)}
            </td>
            <td :if={!@selected} class="py-1.5 pl-4 text-right font-semibold">
              {Format.currency(bar.total, @locale)}
            </td>
            <td :if={@any_last_year?} class="py-1.5 pl-4 text-right">
              <.change now={bar.total} usual={bar.last_year} locale={@locale} />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  def period_choices, do: [week: ~t"Week", month: ~t"Month"]

  # e.g. "Week 45", "November 2026".
  defp heading(:month, start, locale), do: Localize.Date.to_string!(start, locale: locale, format: "LLLL y")
  defp heading(period, start, locale), do: period_label(period, start, locale)

  defp period_heading(:week), do: ~t"Week"
  defp period_heading(:month), do: ~t"Month"

  defp partial do
    gettext_comment(
      "Beside a month whose sales aren't all in: still under way, or begun before the first Winpos report."
    )

    ~t"partial"
  end

  # Under the chart's ends, e.g. "Week 34", "Nov 2025", "2024".
  defp period_label(:week, start, _locale), do: ~t"Week #{week = week_number(start)}"
  defp period_label(:month, start, locale), do: Localize.Date.to_string!(start, locale: locale, format: "LLL y")

  defp bar_name(period, %{partial?: true} = bar, locale), do: "#{period_label(period, bar.start, locale)}, #{partial()}"
  defp bar_name(period, bar, locale), do: period_label(period, bar.start, locale)

  # The rows of labels under the wide chart's bars, one label per bar, nil where it
  # would repeat the one before: months over years, or week numbers over the months
  # their Thursdays fall in, as sales count them, each year named where it starts.
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

  defp last_year_label(:week, last_year, _locale), do: ~t"Week #{week = week_number(last_year.start)} last year"

  defp last_year_label(period, %{partial?: true} = last_year, locale) do
    gettext_comment("A month a year before, counting only the weeks this one has had so far.")
    ~t"#{period = heading(period, last_year.start, locale)}, same weeks"
  end

  defp last_year_label(period, last_year, locale), do: heading(period, last_year.start, locale)

  defp last_year_legend(:week), do: ~t"The same week a year before"
  defp last_year_legend(_period), do: ~t"The same weeks a year before"

  defp group_colour(index), do: Enum.at(@group_colours, index, "bg-base-content/30")

  # Winpos names the groups in Finnish, some with its own numbering.
  defp group_name("3", _winpos_name), do: ~t"Flowers"
  defp group_name("6", _winpos_name), do: ~t"Pots"
  defp group_name("7", _winpos_name), do: ~t"Toys"
  defp group_name("66", _winpos_name), do: ~t"Books and magazines"
  defp group_name(_code, winpos_name), do: winpos_name

  attr :now, Decimal, required: true
  attr :usual, :any, required: true, doc: "a Decimal, or nil when there's nothing to compare with"
  attr :locale, :any, required: true

  # How much more or less than the usual, e.g. "+52 %", always beside both amounts.
  # A dash when there was nothing to compare with.
  defp change(assigns) do
    assigns = assign(assigns, :percent, percent(assigns.now, assigns.usual, assigns.locale))

    ~H"""
    <span :if={@percent} class={trend(@now, @usual)}>{@percent}</span>
    <span :if={!@percent} class="text-base-content/50">–</span>
    """
  end

  # Up green, down red; the sign still says it without the colour. The -content shades
  # are the ones dark enough to read as text.
  defp trend(now, usual) do
    case Decimal.compare(now, usual) do
      :gt -> "text-success-content"
      :lt -> "text-error-content"
      :eq -> "text-base-content/75"
    end
  end

  defp percent(now, usual, locale) do
    if usual && Decimal.positive?(usual) do
      rate = now |> Decimal.div(usual) |> Decimal.sub(1)
      percent = Localize.Number.to_string!(rate, locale: locale, format: :percent, fractional_digits: 0)
      if Decimal.positive?(rate), do: "+" <> percent, else: percent
    end
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

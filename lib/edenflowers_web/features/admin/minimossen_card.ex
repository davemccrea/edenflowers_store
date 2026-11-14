defmodule EdenflowersWeb.Admin.MinimossenCard do
  @moduledoc """
  Minimossen's sales by Winpos product group. `week/1` is the Overview's card: the
  latest week against one yardstick and the weeks before it. `sales/1` draws the
  Minimossen page, which keeps its choices in the URL, with group chips, a scale
  and a table.
  """

  use EdenflowersWeb, {:html, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format

  # The legend's colours, one per group in the chips, bars and table alike.
  # The colours follow the admin's own hue (--chart-* in admin.css).
  # shortcut: a 5th group and later are grey, add a validated colour if Winpos ever has that many.
  @group_colours ~w[bg-(--chart-1) bg-(--chart-2) bg-(--chart-3) bg-(--chart-4)]

  @doc """
  The Minimossen page showing this period and group, and the week or month starting
  `at` in the headline (the latest when nil); the defaults stay out of the URL.
  """
  def page_path(period, group, at \\ nil) do
    query =
      for {key, value} <- [period: period, group: group, at: at],
          value not in [nil, false, :week],
          do: {key, to_string(value)}

    ~p"/admin/minimossen?#{query}"
  end

  attr :sales, :map, required: true, doc: "weekly, from `recent_minimossen_sales`, with at least one week"
  attr :locale, :any, required: true

  def week(assigns) do
    latest = List.last(assigns.sales.periods)
    highest = assigns.sales.periods |> Enum.map(& &1.total) |> Enum.max(Decimal) |> Decimal.to_float()

    assigns =
      assign(assigns,
        latest: latest,
        highest: highest,
        # A seasonal shop's fair yardstick is the same week last year; before there is one, the usual week.
        usual: latest.last_year || latest.average,
        usual_label:
          if(latest.last_year, do: last_year_label(:week, latest.last_year, assigns.locale), else: ~t"8-week average")
      )

    ~H"""
    <.widget id="minimossen" title={~t"Minimossen"} navigate={~p"/admin/minimossen"}>
      <dl>
        <dt class="text-base-content/75 text-sm">
          {period_label(:week, @latest.start, @locale)}
          <span class="text-base-content/60">· {week_dates(@latest.start, @locale)}</span>
        </dt>
        <dd id="minimossen-total" class="text-base-content text-3xl font-semibold tabular-nums tracking-tight">
          {Format.currency(@latest.total, @locale)}
        </dd>
      </dl>
      <p :if={@usual} id="minimossen-change" class="mt-2 flex gap-6 text-sm tabular-nums">
        <span class="text-base-content/75">{@usual_label}</span>
        <span class="text-base-content/75">{Format.currency(@usual.total, @locale)}</span>
        <.change now={@latest.total} usual={@usual.total} locale={@locale} />
      </p>
      <%!-- The trend only; the figures are on the page. --%>
      <figure class="border-base-content/12 mt-4 border-t pt-3" aria-hidden="true">
        <div class="border-base-content/12 flex h-16 items-end gap-1.5 border-b">
          <span
            :for={week <- @sales.periods}
            class={["flex-1", if(week == @latest, do: "bg-primary", else: "bg-primary/30")]}
            style={"height: #{bar_height(week.total, @highest)}%"}
          />
        </div>
        <div class="text-base-content/75 mt-1 flex justify-between text-xs tabular-nums">
          <span>{period_label(:week, hd(@sales.periods).start, @locale)}</span>
          <span>{period_label(:week, @latest.start, @locale)}</span>
        </div>
      </figure>
    </.widget>
    """
  end

  attr :period, :atom, required: true, values: [:week, :month]
  attr :sales, :map, required: true, doc: "from `recent_minimossen_sales`, with at least one period"
  attr :group, :string, default: nil, doc: "the code of the only group shown, or nil for all of them"
  attr :locale, :any, required: true
  attr :at, Date, default: nil, doc: "the start of the period in the headline, or nil for the latest"

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
    # A period that isn't in these reports falls back to the latest.
    shown = Enum.find(assigns.sales.periods, latest, &(&1.start == assigns.at))

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
        shown: shown,
        shown_total: total.(shown),
        average_total: total.(shown.average),
        last_year_total: total.(shown.last_year),
        top: top,
        ticks: ticks,
        bars: bars,
        label_rows: axis_labels(assigns.period, Enum.map(bars, & &1.start), assigns.locale),
        any_last_year?: Enum.any?(bars, & &1.last_year)
      )

    ~H"""
    <div class="lg:flex lg:items-end lg:justify-between lg:gap-10">
      <div>
        <dl>
          <dt class="text-base-content/75 text-sm">
            {@selected && "#{@selected.name} · "}{heading(@period, @shown.start, @locale)}
            <span :if={@period == :week} class="text-base-content/60">· {week_dates(@shown.start, @locale)}</span>
            <span :if={@shown.partial?} class="badge badge-sm badge-ghost ml-1 align-middle">{partial()}</span>
          </dt>
          <dd id="minimossen-total" class="text-base-content text-3xl font-semibold tabular-nums tracking-tight">
            {Format.currency(@shown_total, @locale)}
          </dd>
        </dl>
        <%!-- What the shown period is compared with, so a percentage on a small amount reads for what it is. --%>
        <table :if={@shown.average || @shown.last_year} class="mt-2 text-sm tabular-nums">
          <tbody>
            <tr :if={@shown.average} id="minimossen-change">
              <th scope="row" class="text-base-content/75 pr-6 text-left font-normal">{~t"8-week average"}</th>
              <td class="text-base-content/75 pr-6 text-right">{Format.currency(@average_total, @locale)}</td>
              <td class="text-right"><.change now={@shown_total} usual={@average_total} locale={@locale} /></td>
            </tr>
            <tr :if={@shown.last_year} id="minimossen-last-year">
              <th scope="row" class="text-base-content/75 pr-6 text-left font-normal">
                {last_year_label(@period, @shown.last_year, @locale)}
              </th>
              <td class="text-base-content/75 pr-6 text-right">{Format.currency(@last_year_total, @locale)}</td>
              <td class="text-right"><.change now={@shown_total} usual={@last_year_total} locale={@locale} /></td>
            </tr>
          </tbody>
        </table>
        <.link
          :if={@shown != @latest}
          id="minimossen-latest"
          patch={page_path(@period, @selected && @selected.code)}
          class="text-primary touch-target mt-2 inline-flex items-center gap-1 text-sm hover:underline"
        >
          <.icon name="hero-arrow-uturn-left-micro" class="size-4" />
          {~t"Back to #{period = heading(@period, @latest.start, @locale)}"}
        </.link>
      </div>

      <%!-- The page's legend is also its group filter; the table gives each group's amounts. --%>
      <nav id="minimossen-groups" class="mt-4 flex flex-wrap gap-1 lg:mt-0" aria-label={~t"Show group"}>
        <.link
          :for={{group, label} <- [{nil, ~t"All groups"} | Enum.map(@groups, &{&1, &1.name})]}
          patch={page_path(@period, group && group.code, @shown != @latest && @shown.start)}
          aria-current={@selected == group && "page"}
          class="btn btn-sm rounded-full font-normal shadow-none aria-[current=page]:btn-primary not-aria-[current=page]:btn-ghost"
        >
          <span :if={group} class={[group.colour, "h-2.5 w-2.5 shrink-0"]} /> {label}
        </.link>
      </nav>
    </div>

    <%!-- The page's table carries the figures and its rows pick a period, so its chart is
    only seen and its bars are a pointer's shortcut to the same links. --%>
    <figure class="border-base-content/12 mt-4 border-t pt-3 lg:mt-5 lg:pt-5" aria-hidden="true">
      <div
        id="minimossen-bars"
        class="border-base-content/12 relative flex h-24 items-end justify-center gap-2 border-b lg:ml-14 lg:h-64 lg:gap-3"
      >
        <div
          :for={tick <- @ticks}
          aria-hidden="true"
          class="border-base-content/8 pointer-events-none absolute inset-x-0 hidden border-t lg:block"
          style={"bottom: #{bar_height(tick, @top)}%"}
        >
          <span class="text-base-content/70 absolute right-full -translate-y-1/2 pr-2 text-xs tabular-nums">
            {Format.storefront_price(Decimal.from_float(tick), @locale)}
          </span>
        </div>
        <.link
          :for={{bar, index} <- Enum.with_index(@bars)}
          patch={page_path(@period, @selected && @selected.code, bar != List.last(@bars) && bar.start)}
          tabindex="-1"
          aria-current={bar.start == @shown.start && "true"}
          class="group/bar max-w-24 relative flex h-full flex-1 flex-col justify-end gap-0.5 aria-[current]:bg-base-content/8 hover:bg-base-content/6"
        >
          <%!-- Relative, so the segments paint over the hover fill. --%>
          <span
            :for={group <- @stacked}
            class={["relative block", if(@selected in [nil, group], do: group.colour, else: "bg-base-content/10")]}
            style={"height: #{bar_height(bar.groups[group.code], @top)}%"}
          />
          <%!-- The same period a year before, like for like while under way: a tick in front
          of the bar and a little wider, so it reads whether this year is higher or lower. --%>
          <span
            :if={bar.last_year}
            class="bg-base-content ring-base-100 z-[1] pointer-events-none absolute -inset-x-1 h-0.5 translate-y-1/2 ring-1"
            style={"bottom: #{bar_height(bar.last_year, @top)}%"}
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
            class={["bg-base-100 border-base-content/12 text-base-content pointer-events-none absolute z-10 hidden text-left font-normal", "whitespace-nowrap border px-2.5 py-1.5 text-xs shadow-sm", "group-hover/bar:block", if(index < length(@bars) / 2, do: "left-0", else: "right-0")]}
          >
            <span class="text-base-content block font-semibold">{bar_name(@period, bar, @locale)}</span>
            <%!-- Top to bottom, as the bar stacks them. --%>
            <span :for={group <- Enum.reverse(@listed)} class="flex items-center gap-1.5">
              <span class={[group.colour, "h-2 w-2 shrink-0"]} />
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
                <span class="bg-base-content h-0.5 w-2.5" />{~t"A year before"}
              </span>
              <span class="tabular-nums">{Format.currency(bar.last_year, @locale)}</span>
            </span>
          </span>
        </.link>
      </div>
      <div class="text-base-content/75 mt-1 flex justify-between text-xs tabular-nums lg:hidden">
        <span>{period_label(@period, hd(@bars).start, @locale)}</span>
        <span>{period_label(@period, @latest.start, @locale)}</span>
      </div>
      <%!-- On a large screen, a label under each bar, matching the bars' gap. --%>
      <div
        :for={{labels, row} <- Enum.with_index(@label_rows)}
        class="text-base-content/75 mt-1 ml-14 hidden justify-center gap-3 text-xs tabular-nums lg:flex"
      >
        <span
          :for={{label, bar} <- Enum.zip(labels, @bars)}
          class={["max-w-24 min-w-0 flex-1 whitespace-nowrap text-center", row == 0 and bar.start == @shown.start and "text-base-content font-semibold"]}
        >
          {label}
        </span>
      </div>
      <figcaption :if={@any_last_year?} class="text-base-content/75 mt-2 flex items-center gap-1.5 text-xs">
        <span class="bg-base-content h-0.5 w-3" aria-hidden="true" />
        {last_year_legend(@period)}
      </figcaption>
    </figure>

    <%!-- As wide as its columns, so an amount stays near its period with few groups. --%>
    <div class="mt-6 overflow-x-auto">
      <table id="minimossen-table" class="w-full text-sm tabular-nums sm:w-auto">
        <thead class="text-base-content/70 text-xs">
          <tr class="border-base-content/12 border-b">
            <th scope="col" class="pr-6 pb-2 text-left font-medium">{period_heading(@period)}</th>
            <%!-- On a phone, all groups give way to the total and the change. --%>
            <th
              :for={group <- @listed}
              scope="col"
              class={["pb-2 pl-6 text-right font-medium", !@selected && "hidden sm:table-cell"]}
            >
              <span class="max-w-32 inline-flex items-center gap-1.5" title={group.name}>
                <span class={[group.colour, "h-2 w-2 shrink-0"]} />
                <span class="truncate">{group.name}</span>
              </span>
            </th>
            <th :if={!@selected} scope="col" class="pb-2 pl-6 text-right font-medium">{~t"Total"}</th>
            <th :if={@any_last_year?} scope="col" class="pb-2 pl-6 text-right font-medium">
              {~t"vs. a year before"}
            </th>
          </tr>
        </thead>
        <tbody class="divide-base-content/8 divide-y">
          <tr
            :for={bar <- Enum.reverse(@bars)}
            aria-current={bar.start == @shown.start && "true"}
            class="aria-[current]:bg-base-content/6"
          >
            <th scope="row" class="whitespace-nowrap py-1.5 pr-6 text-left font-normal">
              <.link
                patch={page_path(@period, @selected && @selected.code, bar != List.last(@bars) && bar.start)}
                class="hover:underline"
              >
                {period_label(@period, bar.start, @locale)}
              </.link>
              <span :if={bar.partial?} class="badge badge-xs badge-ghost ml-1">{partial()}</span>
            </th>
            <td
              :for={group <- @listed}
              class={["text-base-content/75 py-1.5 pl-6 text-right", !@selected && "hidden sm:table-cell"]}
            >
              {Format.currency(bar.groups[group.code], @locale)}
            </td>
            <td :if={!@selected} class="py-1.5 pl-6 text-right font-semibold">
              {Format.currency(bar.total, @locale)}
            </td>
            <td :if={@any_last_year?} class="py-1.5 pl-6 text-right">
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

  # e.g. "3–9 Nov", "27 Oct–2 Nov".
  defp week_dates(start, locale) do
    finish = Date.add(start, 6)
    month = &Format.short_month(&1, locale)

    if start.month == finish.month,
      do: "#{start.day}–#{finish.day} #{month.(finish)}",
      else: "#{start.day} #{month.(start)}–#{finish.day} #{month.(finish)}"
  end

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

  # The rows of labels under the chart's bars on a large screen, one label per bar, nil where it
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
  defp last_year_legend(_period), do: ~t"The same month a year before"

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
      # A real minus in every locale, as wide as the plus.
      if Decimal.positive?(rate), do: "+" <> percent, else: String.replace(percent, "-", "−")
    end
  end

  # A scale of 2 to 5 round steps with the lowest top, and the amount at its top.
  # Some step always fits: 2 × 10ⁿ for 2 to 5 steps, 0.5 × 10ⁿ for 2 to 4.
  defp scale(highest) when highest == 0, do: {0.0, []}

  defp scale(highest) do
    magnitude = :math.pow(10, Float.floor(:math.log10(highest)))

    {step, steps} =
      [0.1, 0.2, 0.25, 0.5, 1, 2]
      |> Enum.map(&{&1 * magnitude, ceil(highest / (&1 * magnitude))})
      |> Enum.filter(fn {_step, steps} -> steps in 2..5 end)
      |> Enum.min_by(fn {step, steps} -> {step * steps, steps} end)

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

defmodule EdenflowersWeb.Admin.OverviewLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Catalog
  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Orders
  alias EdenflowersWeb.Admin.PushSubscriptions
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EdenflowersWeb.Endpoint.subscribe("admin:orders")
      EdenflowersWeb.Endpoint.subscribe("admin:bookings")
    end

    {:ok,
     socket
     |> assign(:page_title, ~t"Overview")
     |> assign(:locale, Localize.get_locale())
     |> assign(:vapid_public_key, Edenflowers.WebPush.public_key())
     |> assign(:report_month, previous_month())
     |> assign(:calendar, Fulfillment.get_shop_calendar!(actor: socket.assigns.current_user))
     |> assign_orders()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={greeting(@current_user)}>
          <:menu>
            <.button navigate={~p"/admin/orders/new"} variant="primary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" /> {~t"New order"}
            </.button>
          </:menu>
        </.admin_page_header>

        <.notifications_offer :if={@vapid_public_key} vapid_public_key={@vapid_public_key} />

        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:grid-rows-[max-content_max-content_1fr] xl:items-start">
          <.attention_widget :if={@attention != []} groups={@attention} locale={@locale} />
          <div class="min-w-0 space-y-6 xl:col-start-1 xl:row-span-3 xl:row-start-1">
            <.days_card
              days={@days}
              day={selected_day(@day, @days)}
              orders_by_date={@orders_by_date}
              calendar={@calendar}
              today={@today}
              locale={@locale}
            />
          </div>
          <div class="min-w-0 xl:col-start-2">
            <.sales_widget
              sales={@sales}
              last_month={@last_month_sales}
              last_month_whole={@last_month_whole}
              last_month_to={@last_month_to}
              today={@today}
              owed={@owed}
              locale={@locale}
            />
          </div>
          <div class="min-w-0 xl:col-start-2">
            <.report_widget month={@report_month} />
          </div>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_params(params, _uri, socket) do
    day =
      case Date.from_iso8601(params["day"] || "") do
        {:ok, date} -> date
        {:error, _} -> nil
      end

    {:noreply, assign(socket, :day, day)}
  end

  @impl true
  def handle_event("push_subscribed", params, socket),
    do: {:reply, PushSubscriptions.subscribe(params, socket.assigns.current_user), socket}

  # Only today, so a page left open overnight can't toggle yesterday.
  def handle_event("toggle-date", %{"date" => date}, socket) do
    date = Date.from_iso8601!(date)
    %{calendar: calendar, current_user: actor} = socket.assigns

    if date == Edenflowers.ShopTime.today() and booking(calendar, date) do
      {:noreply, assign(socket, :calendar, Fulfillment.toggle_date!(calendar, date, actor: actor))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, assign_orders(socket)}

  # Whether customers can book `date` (:open), Jennie closed just that day (:closed),
  # or neither, when the weekday rule, same-day setting or deadline already shut it.
  defp booking(calendar, date) do
    now = Edenflowers.ShopTime.now()

    cond do
      Date.before?(date, DateTime.to_date(now)) -> nil
      date in calendar.disabled_dates -> :closed
      is_nil(Availability.unavailable_reason(calendar, date, now)) -> :open
      true -> nil
    end
  end

  # A day off the strip, such as yesterday's after midnight, falls back to today.
  defp selected_day(day, [today | _] = days), do: if(day in days, do: day, else: today)

  defp greeting(%{first_name: first_name}) when is_binary(first_name), do: ~t"Hi, #{first_name}"

  defp greeting(_user), do: ~t"Hi"

  defp assign_orders(socket) do
    actor = socket.assigns.current_user
    today = Edenflowers.ShopTime.today()

    {overdue, due} =
      Orders.list_orders_due_soon!(actor: actor)
      |> Enum.split_with(&Date.before?(&1.fulfillment_date, today))

    {owed, to_refund} = actor |> balance_rows() |> Enum.split_with(&Decimal.positive?(&1.amount))
    payment_overdue = Enum.filter(owed, & &1.overdue?)

    attention =
      Enum.reject(
        [
          {"overdue-orders", "hero-clock", ~t"Overdue orders", Enum.map(overdue, &overdue_order_row/1)},
          {"failed-subscriptions", "hero-credit-card", ~t"Subscription payment failed",
           Enum.map(Orders.list_failed_subscriptions!(actor: actor), &subscription_row/1)},
          {"refund", "hero-arrow-uturn-left", ~t"To refund", to_refund},
          {"payment-overdue", "hero-banknotes", ~t"Payment overdue", payment_overdue},
          {"sold-out", "hero-archive-box-x-mark", ~t"Sold out",
           Enum.map(Catalog.list_sold_out_variants!(actor: actor), &sold_out_row/1)}
        ],
        fn {_key, _icon, _title, rows} -> rows == [] end
      )

    # Date.shift clamps to the month's last day, so 31.3. compares with 28.2.
    same_day_last_month = Date.shift(today, month: -1)

    socket
    |> assign(:days, Enum.to_list(Date.range(today, Date.add(today, 8))))
    |> assign(:orders_by_date, Enum.group_by(due, & &1.fulfillment_date))
    |> assign(:attention, attention)
    |> assign(:today, today)
    |> assign(:owed, owed |> Enum.filter(&(&1.kind == :order)) |> sum_amounts())
    |> assign(:sales, Orders.sales_summary!(Date.beginning_of_month(today), today, actor: actor))
    |> assign(:last_month_to, same_day_last_month)
    |> assign(
      :last_month_whole,
      Orders.sales_summary!(
        Date.beginning_of_month(same_day_last_month),
        Date.end_of_month(same_day_last_month),
        actor: actor
      )
    )
    |> assign(
      :last_month_sales,
      Orders.sales_summary!(Date.beginning_of_month(same_day_last_month), same_day_last_month, actor: actor)
    )
  end

  # Largest first, either way.
  defp balance_rows(actor) do
    order_rows =
      for order <- Orders.list_unsettled_orders!(actor: actor) do
        %{
          id: "order-#{order.id}",
          who: order.customer_name || order.order_reference,
          what: if(order.customer_name, do: order.order_reference),
          kind: :order,
          amount: order.balance,
          overdue?: order.payment_overdue?,
          href: ~p"/admin/orders/#{order.id}"
        }
      end

    booking_rows =
      for registration <- Courses.list_unsettled_registrations!(actor: actor) do
        %{
          id: "booking-#{registration.id}",
          who: registration.name,
          what: registration.course.name,
          kind: :booking,
          amount: registration.balance,
          overdue?: registration.payment_overdue?,
          href: ~p"/admin/courses?#{[booking: registration.id]}" <> "#registration-#{registration.id}"
        }
      end

    Enum.sort_by(order_rows ++ booking_rows, &Decimal.abs(&1.amount), {:desc, Decimal})
  end

  defp order_row_link(order) do
    %{
      id: "order-#{order.id}",
      who: order.customer_name || ~t"Unnamed customer",
      what: Format.weekday_day_month(order.fulfillment_date, Format.locale()),
      href: ~p"/admin/orders/#{order.id}"
    }
  end

  defp overdue_order_row(order) do
    row = order_row_link(order)
    %{row | what: "#{row.what} · #{fulfillment_method_label(order.fulfillment_method)}"}
  end

  defp subscription_row(subscription) do
    %{
      id: "subscription-#{subscription.id}",
      who: subscription.user.name || ~t"Unnamed customer",
      what: subscription.product_variant.product.name,
      href: ~p"/admin/subscriptions/#{subscription.id}"
    }
  end

  defp sold_out_row(variant) do
    %{
      id: "variant-#{variant.id}",
      who: variant.product.name,
      what: variant.size && variant_size_label(variant.size),
      href: ~p"/admin/products/#{variant.product_id}"
    }
  end

  attr :vapid_public_key, :string, required: true

  # Starts hidden: the PushNudge hook shows it only in the installed app, before
  # it has asked for notification permission.
  defp notifications_offer(assigns) do
    ~H"""
    <section
      id="notifications-offer"
      phx-hook="PushNudge"
      phx-update="ignore"
      hidden
      data-vapid-public-key={@vapid_public_key}
      aria-labelledby="notifications-offer-title"
      class="admin-card mb-6 flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5"
    >
      <div class="flex items-start gap-3">
        <.icon name="hero-bell" class="text-primary mt-0.5 h-5 w-5 shrink-0" />
        <div>
          <h2 id="notifications-offer-title" class="text-base-content text-base font-semibold">
            {~t"Get new orders on this phone"}
          </h2>
          <p class="text-base-content/65 text-sm">{~t"Same-day orders arrive straight away."}</p>
        </div>
      </div>
      <div class="flex justify-end gap-2">
        <.button type="button" variant="ghost" size="sm" data-push-nudge="dismiss">{~t"Not now"}</.button>
        <.button type="button" variant="primary" size="sm" data-push-nudge="enable">{~t"Turn on"}</.button>
      </div>
    </section>
    """
  end

  attr :sales, :map, required: true, doc: "this month to today, from `sales_summary`"
  attr :last_month, :map, required: true, doc: "last month to `last_month_to`"
  attr :last_month_whole, :map, required: true, doc: "all of last month, for the chart"
  attr :last_month_to, Date, required: true
  attr :today, Date, required: true
  attr :owed, :any, required: true, doc: "what placed orders still owe, overdue or not"
  attr :locale, :any, required: true

  defp sales_widget(assigns) do
    assigns =
      assign(assigns, :chart, pace_chart(assigns.sales.revenue_by_day, assigns.last_month_whole.revenue_by_day))

    ~H"""
    <.widget title={~t"This month"}>
      <div class="grid-cols-[minmax(0,1fr)_auto] grid items-start gap-x-6">
        <dl id="revenue" class="min-w-0">
          <dt class="text-base-content/65 text-sm">{~t"Revenue"}</dt>
          <dd class="text-base-content text-3xl font-semibold tabular-nums tracking-tight">
            {Format.currency(@sales.revenue, @locale)}
          </dd>
          <dd id="revenue-last-month" class="text-base-content/65 mt-0.5 text-xs tabular-nums">
            {~t"#{amount = Format.currency(@last_month.revenue, @locale)} last month by #{date = Format.day_month(@last_month_to, @locale)}"}
          </dd>
        </dl>

        <div class="text-right">
          <dl id="sales">
            <dt class="text-base-content/65 text-sm">{~t"Sales"}</dt>
            <dd class="text-base-content text-3xl font-semibold tabular-nums tracking-tight">{@sales.order_count}</dd>
          </dl>
          <p id="sales-last-month" class="text-base-content/65 mt-0.5 text-xs tabular-nums">
            {~t"#{count = @last_month.order_count} last month by #{date = Format.day_month(@last_month_to, @locale)}"}
          </p>
        </div>
      </div>

      <figure id="revenue-pace" class="mt-4" aria-hidden="true">
        <div class="border-base-content/20 relative h-24 border-b">
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" class="absolute inset-0 h-full w-full overflow-visible">
            <path d={@chart.this_area} class="fill-primary/12" />
            <path
              d={@chart.last_line}
              fill="none"
              stroke-dasharray="3 3"
              vector-effect="non-scaling-stroke"
              class="stroke-base-content/35 stroke-[1.5]"
            />
            <path
              d={@chart.this_line}
              fill="none"
              stroke-linejoin="round"
              vector-effect="non-scaling-stroke"
              class="stroke-primary stroke-2"
            />
          </svg>
          <span
            class="bg-primary ring-base-100 absolute h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full ring-2"
            style={"left: #{@chart.today_x}%; top: #{@chart.today_y}%"}
          />
        </div>
        <div class="text-base-content/65 mt-1 flex justify-between text-xs tabular-nums">
          <span>{Format.day_month(Date.beginning_of_month(@today), @locale)}</span>
          <span>{Format.day_month(Date.end_of_month(@today), @locale)}</span>
        </div>
        <figcaption class="text-base-content/65 mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs">
          <span class="flex items-center gap-1.5">
            <span class="bg-primary h-0.5 w-4 rounded-full" /> {~t"This month"}
          </span>
          <span class="flex items-center gap-1.5">
            <span class="border-base-content/35 border-t-[1.5px] w-4 border-dashed" />
            {~t"Last month"}
            <span class="text-base-content/85 tabular-nums">{Format.currency(@last_month_whole.revenue, @locale)}</span>
          </span>
        </figcaption>
      </figure>

      <p
        :if={Decimal.positive?(@owed)}
        id="still-owed"
        class="border-base-content/12 text-base-content/65 mt-4 flex items-baseline justify-between gap-4 border-t pt-3 text-sm"
      >
        {~t"Still to come in"}
        <span class="text-base-content font-medium tabular-nums">{Format.currency(@owed, @locale)}</span>
      </p>
    </.widget>
    """
  end

  # Running revenue totals by day of month, in a 100×100 box with the y-axis
  # flipped, so this month reads against where last month stood on the same day.
  defp pace_chart(this_month, last_month) do
    this = running_totals(this_month)
    last = running_totals(last_month)
    span = max(Date.days_in_month(hd(this_month).date), length(last_month))
    values = this ++ last
    low = min(0, Enum.min(values))
    high = max(Enum.max(values), low + 1)

    point = fn index, value ->
      {Float.round(index / (span - 1) * 100, 2), Float.round(96 - (value - low) / (high - low) * 92, 2)}
    end

    this_points = this |> Enum.with_index() |> Enum.map(fn {value, index} -> point.(index, value) end)
    last_points = last |> Enum.with_index() |> Enum.map(fn {value, index} -> point.(index, value) end)
    {today_x, today_y} = List.last(this_points)
    {_, baseline} = point.(0, low)

    %{
      this_line: svg_path(this_points),
      this_area: svg_path(this_points) <> " L#{today_x},#{baseline} L0,#{baseline} Z",
      last_line: svg_path(last_points),
      today_x: today_x,
      today_y: today_y
    }
  end

  defp running_totals(days) do
    days
    |> Enum.scan(Decimal.new(0), &Decimal.add(&1.revenue, &2))
    |> Enum.map(&Decimal.to_float/1)
  end

  defp svg_path([{x, y} | rest]), do: Enum.reduce(rest, "M#{x},#{y}", fn {x, y}, path -> path <> " L#{x},#{y}" end)

  attr :month, :string, required: true

  # A plain GET, not a LiveView event, so the browser downloads the zip itself. The
  # new tab loads while the zip builds and closes once the download starts; on an
  # error it shows Overview with the flash.
  defp report_widget(assigns) do
    ~H"""
    <.widget title={~t"Accountant report"}>
      <form
        id="report-form"
        action={~p"/admin/reports"}
        method="get"
        target="_blank"
        class="flex flex-wrap items-end gap-3"
      >
        <label class="min-w-40 flex flex-1 flex-col gap-1 text-sm">
          {~t"Month"}
          <input type="month" name="month" value={@month} required class="input w-full" />
        </label>
        <.button type="submit" variant="secondary">
          <.icon name="hero-arrow-down-tray" class="h-4 w-4" />
          {~t"Download"}
        </.button>
      </form>
    </.widget>
    """
  end

  defp previous_month do
    Edenflowers.ShopTime.today()
    |> Date.beginning_of_month()
    |> Date.add(-1)
    |> Date.to_iso8601()
    |> String.slice(0, 7)
  end

  attr :groups, :list, required: true, doc: "`{key, icon, title, rows}`, each with at least one row"
  attr :locale, :any, required: true

  # Collapsed to a line per kind of problem, so it stays short on a phone.
  defp attention_widget(assigns) do
    ~H"""
    <section
      id="attention"
      aria-labelledby="attention-title"
      class="admin-card border-amber-600/25 bg-amber-50/40 min-w-0 p-4 sm:p-5 xl:col-start-2"
    >
      <h2 id="attention-title" class="text-base-content mb-2 flex items-center gap-2 text-base font-semibold">
        <.icon name="hero-exclamation-triangle" class="text-warning h-5 w-5" />
        {~t"Needs attention"}
      </h2>
      <ul class="divide-amber-900/10 divide-y text-sm">
        <li :for={{key, icon, title, rows} <- @groups}>
          <details id={"attention-#{key}"} phx-mounted={JS.ignore_attributes(["open"])} class="group">
            <summary class="touch-target flex cursor-pointer list-none items-center gap-3 py-2">
              <.icon name={icon} class="text-amber-800/70 h-4 w-4 shrink-0" />
              <span class="text-base-content flex min-w-0 flex-1 flex-wrap items-center gap-2">
                {title}
                <.count_badge count={length(rows)} active={true} tone={:warning} />
              </span>
              <span :if={Map.has_key?(hd(rows), :amount)} class="text-base-content shrink-0 tabular-nums">
                {Format.currency(sum_amounts(rows), @locale)}
              </span>
              <.icon
                name="hero-chevron-down"
                class="text-amber-800/60 h-4 w-4 shrink-0 transition-transform group-open:rotate-180"
              />
            </summary>
            <ul class="border-amber-600/25 divide-amber-900/10 mb-2 ml-2 divide-y border-l pl-5">
              <.link_row :for={row <- rows} id={"attention-#{key}-#{row.id}"} row={row} locale={@locale} />
            </ul>
          </details>
        </li>
      </ul>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true, doc: "`who`, `what` (or nil), `href`, and an optional `amount`"
  attr :locale, :any, required: true

  defp link_row(assigns) do
    ~H"""
    <li id={@id}>
      <.link
        navigate={@row.href}
        class="-mx-2 flex items-baseline justify-between gap-4 px-2 py-2 transition-colors hover:bg-amber-900/5"
      >
        <span class="min-w-0">
          <span class="text-base-content block truncate font-medium">{@row.who}</span>
          <span :if={@row.what} class="text-base-content/65 block truncate text-sm">{@row.what}</span>
        </span>
        <span :if={@row[:amount]} class="text-base-content shrink-0 tabular-nums">
          {Format.currency(Decimal.abs(@row.amount), @locale)}
        </span>
      </.link>
    </li>
    """
  end

  defp sum_amounts(rows), do: rows |> Enum.map(&Decimal.abs(&1.amount)) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

  attr :id, :string, required: true
  attr :texts, :any, required: true, doc: "`{label, empty}` from `day_texts/2`"
  attr :date, Date, required: true
  attr :orders, :list, required: true
  attr :booking, :atom, required: true, doc: "`:open`, `:closed` or nil, see `booking/2`"
  attr :locale, :any, required: true
  attr :class, :any, default: nil

  defp day_section(assigns) do
    {label, empty} = assigns.texts
    assigns = assign(assigns, label: label, empty: empty)

    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-title"} class={@class}>
      <div class="mb-4 flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
        <div class="min-w-0">
          <h2 id={"#{@id}-title"} class="text-base-content flex flex-wrap items-center gap-2 text-lg font-semibold">
            {@label || Format.weekday_day_month(@date, @locale)}
            <.badge :if={@booking == :closed} id={"#{@id}-closed"} tone={:warning}>{~t"Closed"}</.badge>
          </h2>
        </div>
        <.button
          :if={@booking}
          id={"#{@id}-toggle"}
          type="button"
          variant="ghost"
          size="sm"
          aria-describedby={"#{@id}-title"}
          phx-click="toggle-date"
          phx-value-date={Date.to_iso8601(@date)}
        >
          <%= if @booking == :open do %>
            <.icon name="hero-no-symbol" class="h-4 w-4" /> {~t"Stop orders"}
          <% else %>
            <.icon name="hero-arrow-path" class="h-4 w-4" /> {~t"Reopen orders"}
          <% end %>
        </.button>
      </div>

      <div class="space-y-4">
        <div :for={{method, orders} <- by_method(@orders)} id={"#{@id}-#{method}"}>
          <h3 class="eyebrow text-base-content/65 flex items-center gap-1.5 pb-1">
            <.icon name={fulfillment_method_icon(method)} class="text-base-content/50 h-4 w-4 shrink-0" />
            {method_heading(method)}
            <.count_badge :if={length(orders) < length(@orders)} count={length(orders)} active={true} />
          </h3>
          <ul class="divide-base-content/8 -mx-4 divide-y sm:-mx-5">
            <.order_row :for={order <- orders} order={order} />
          </ul>
        </div>
      </div>

      <p :if={@orders == []} class="text-base-content/65 flex items-center gap-2 py-5 text-sm">
        <.icon name="hero-check-circle" class="h-5 w-5 shrink-0" />
        {@empty}
      </p>
    </section>
    """
  end

  attr :days, :list, required: true, doc: "today and the 8 days after it"
  attr :day, Date, required: true, doc: "the day whose orders are listed"
  attr :orders_by_date, :map, required: true
  attr :calendar, :map, required: true
  attr :today, Date, required: true
  attr :locale, :any, required: true

  # Nine days because Jennie buys from the wholesaler anywhere from a day to a week ahead.
  defp days_card(assigns) do
    ~H"""
    <div class="admin-card p-4 sm:p-5">
      <%!-- Scrolls sideways on a phone, bleeding to the card's edges. --%>
      <ol
        id="days"
        phx-hook="ScrollToCurrent"
        aria-label={~t"Days"}
        class="admin-scroll-fade [scrollbar-width:none] relative -mx-4 flex snap-x scroll-px-4 gap-1 overflow-x-auto px-4 sm:mx-0 sm:grid sm:grid-cols-9 sm:overflow-visible sm:px-0"
      >
        <li :for={date <- @days} id={"day-#{date}"} class="w-13 shrink-0 snap-start sm:w-auto">
          <.day_cell
            date={date}
            count={length(Map.get(@orders_by_date, date, []))}
            closed?={Availability.customer_cell_state(@calendar, date) == :closed}
            selected?={date == @day}
            today?={date == @today}
            locale={@locale}
          />
        </li>
      </ol>

      <.day_section
        id="day-orders"
        texts={day_texts(@day, @today)}
        date={@day}
        orders={Map.get(@orders_by_date, @day, [])}
        booking={if @day == @today, do: booking(@calendar, @day)}
        locale={@locale}
        class="border-base-content/12 mt-4 border-t pt-4"
      />

      <div class="border-base-content/12 mt-5 border-t pt-3">
        <.link navigate={~p"/admin/orders"} class="text-primary touch-target inline-block py-1 text-sm hover:underline">
          {~t"View all orders"} →
        </.link>
      </div>
    </div>
    """
  end

  attr :date, Date, required: true
  attr :count, :integer, required: true
  attr :closed?, :boolean, required: true
  attr :selected?, :boolean, required: true
  attr :today?, :boolean, required: true
  attr :locale, :any, required: true

  # The count sits in a badge so it can't be read as part of the date. A closed day
  # is muted but still shows its orders, such as a custom order taken anyway.
  defp day_cell(assigns) do
    ~H"""
    <.link
      patch={if @today?, do: ~p"/admin", else: ~p"/admin?#{[day: Date.to_iso8601(@date)]}"}
      aria-current={@selected? && "true"}
      aria-label={day_cell_label(@date, @count, @closed?, @locale)}
      class={["flex flex-col items-center gap-0.5 rounded-lg py-2 transition-colors", day_cell_class(@selected?, @closed?)]}
    >
      <span class={["text-xs", !@selected? && !@closed? && "text-base-content/65"]}>
        {Localize.Date.to_string!(@date, locale: @locale, format: "ccc")}
      </span>
      <span class={["text-sm font-medium tabular-nums", @today? && "underline decoration-2 underline-offset-4"]}>
        {@date.day}
      </span>
      <span class="flex h-5 items-center">
        <span
          :if={@count > 0}
          class={["badge badge-sm rounded-full border-0 font-semibold tabular-nums", if(@selected?, do: "bg-primary-content/20 text-primary-content", else: "bg-primary/10 text-primary")]}
        >
          {@count}
        </span>
        <.icon :if={@count == 0 and @closed?} name="hero-no-symbol" class="h-4 w-4" />
      </span>
    </.link>
    """
  end

  defp day_cell_class(true = _selected?, _closed?), do: "bg-primary text-primary-content"
  defp day_cell_class(false, true), do: "bg-base-200/70 text-base-content/40 hover:bg-base-200"
  defp day_cell_class(false, false), do: "hover:bg-base-200/60"

  defp day_cell_label(date, count, closed?, locale) do
    [
      Format.weekday_day_month(date, locale),
      closed? && ~t"Closed",
      count > 0 && ~t"#{count = count} order(s)"N
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  # `{label, empty}`; further out than tomorrow the heading is the date itself.
  defp day_texts(date, today) do
    case Date.diff(date, today) do
      0 -> {~t"Today", ~t"Nothing to make today"}
      1 -> {~t"Tomorrow", ~t"Nothing to make tomorrow"}
      _ -> {nil, ~t"Nothing to make"}
    end
  end

  attr :order, :map, required: true

  # What the florist needs to act on, in reading order: whose order, what to make,
  # whether there's a card to write, and when it leaves the shop. Price lives on the
  # order page; it doesn't change what gets made.
  defp order_row(assigns) do
    assigns = assign(assigns, :items, Enum.reject(assigns.order.line_items, & &1.is_card))

    ~H"""
    <li>
      <.link
        navigate={~p"/admin/orders/#{@order.id}"}
        class="grid-cols-[minmax(0,1fr)_auto] grid items-start gap-x-3 px-4 py-3.5 transition-colors hover:bg-base-200/60 focus-visible:-outline-offset-2 sm:px-5"
      >
        <div class="min-w-0">
          <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
            <span class="text-base-content min-w-0 break-words font-semibold">
              {@order.customer_name || ~t"Unnamed customer"}
            </span>
          </div>

          <ul :if={@items != []} class="text-base-content mt-1 space-y-0.5 text-sm">
            <li :for={item <- @items} class="break-words" phx-no-format>
              <span class="font-semibold tabular-nums">{item.quantity} ×</span>
              <span class="font-medium">{item.product_name}</span><span :if={item.variant_size} class="text-base-content/65">, {variant_size_label(item.variant_size)}</span>
            </li>
          </ul>

          <p
            :if={present?(@order.florist_note)}
            class="text-base-content/85 line-clamp-2 mt-1 text-sm italic"
            data-testid="florist-note"
          >
            <.icon name="hero-chat-bubble-bottom-center-text" class="text-base-content/50 align-[-2px] mr-1 h-3.5 w-3.5" />{@order.florist_note}
          </p>

          <div class="mt-1.5 flex flex-wrap items-center gap-1 empty:hidden">
            <.gift_badge :if={@order.gift} recipient_name={presence(@order.recipient_name)} />
            <.badge :if={present?(@order.card_message)} tone={:neutral} icon="hero-pencil-square">
              {~t"Card to write"}
            </.badge>
            <.badge :if={@order.missing_delivery_phone?} tone={:warning} icon="hero-phone-x-mark">
              {~t"Missing recipient phone"}
            </.badge>
            <.badge :if={Decimal.positive?(@order.balance)} tone={:warning}>
              <%= if Decimal.positive?(@order.amount_paid) do %>
                {~t"To collect #{amount = Format.currency(@order.balance, Format.locale())}"}
              <% else %>
                {~t"Unpaid"}
              <% end %>
            </.badge>
          </div>
        </div>

        <div class="flex shrink-0 flex-col items-end gap-0.5 pt-0.5 text-right">
          <span
            :if={Format.fulfillment_time_range(@order, Format.locale())}
            class="text-base-content flex items-center gap-1 whitespace-nowrap text-xs font-medium tabular-nums sm:text-sm"
            data-testid="fulfillment-time"
          >
            <.icon name="hero-clock" class="text-base-content/50 h-3.5 w-3.5" />
            {Format.fulfillment_time_range(@order, Format.locale())}
          </span>
          <span :if={@order.distance_km} class="text-base-content/65 text-xs tabular-nums">
            {@order.distance_km} km
          </span>
        </div>
      </.link>
    </li>
    """
  end

  # Deliveries go out on a run, so they come first; the read already sorts each by time and distance.
  defp by_method(orders) do
    for method <- [:delivery, :pickup],
        group = Enum.filter(orders, &(&1.fulfillment_method == method)),
        group != [],
        do: {method, group}
  end

  defp method_heading(:delivery), do: ~t"Deliveries"
  defp method_heading(:pickup), do: ~t"Pickups"
end

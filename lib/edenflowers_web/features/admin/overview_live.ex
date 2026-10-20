defmodule EdenflowersWeb.Admin.OverviewLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Courses
  alias Edenflowers.Format
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
     |> assign_orders()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={greeting(@current_user)}>
          <:actions>
            <.button navigate={~p"/admin/orders/new"} variant="primary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" /> {~t"New order"}
            </.button>
          </:actions>
        </.admin_page_header>

        <.notifications_offer :if={@vapid_public_key} vapid_public_key={@vapid_public_key} />

        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <div class="flex min-w-0 flex-col gap-6">
            <.day_widget
              id="orders-today"
              title={~t"Today"}
              orders={@today_orders}
              overdue={@overdue_orders}
              empty={~t"Nothing to make today"}
              locale={@locale}
            />
            <.day_widget
              id="orders-tomorrow"
              title={~t"Tomorrow"}
              orders={@tomorrow_orders}
              empty={~t"Nothing to make tomorrow"}
              locale={@locale}
            />
            <.link
              navigate={~p"/admin/orders"}
              class="text-primary touch-target -mt-3 inline-block self-start py-1 text-sm hover:underline"
            >
              {~t"View all orders"} →
            </.link>
          </div>
          <aside class="flex min-w-0 flex-col gap-6">
            <.balances_widget :if={@balances != []} balances={@balances} locale={@locale} />
            <.sales_widget sales_count={@sales_count} revenue={@revenue} locale={@locale} />
            <.report_widget month={@report_month} />
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("push_subscribed", params, socket),
    do: {:reply, PushSubscriptions.subscribe(params, socket.assigns.current_user), socket}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, assign_orders(socket)}

  defp greeting(%{first_name: first_name}) when is_binary(first_name), do: ~t"Hi, #{first_name}"

  defp greeting(_user), do: ~t"Hi"

  defp assign_orders(socket) do
    actor = socket.assigns.current_user
    today = Edenflowers.ShopTime.today()

    orders_by_day =
      Orders.list_orders_due_by_tomorrow!(actor: actor)
      |> Enum.group_by(&day(&1.fulfillment_date, today))

    sales = Orders.sales_summary!(Date.beginning_of_month(today), today, actor: actor)

    socket
    |> assign(:overdue_orders, Map.get(orders_by_day, :overdue, []))
    |> assign(:today_orders, Map.get(orders_by_day, :today, []))
    |> assign(:tomorrow_orders, Map.get(orders_by_day, :tomorrow, []))
    |> assign(:sales_count, sales.order_count)
    |> assign(:revenue, sales.revenue)
    |> assign(:balances, balances(actor))
  end

  defp balances(actor) do
    order_rows =
      for order <- Orders.list_unsettled_orders!(actor: actor) do
        %{
          id: "order-#{order.id}",
          who: order.customer_name || order.order_reference,
          what: if(order.customer_name, do: order.order_reference),
          balance: order.balance,
          href: ~p"/admin/orders/#{order.id}"
        }
      end

    booking_rows =
      for registration <- Courses.list_unsettled_registrations!(actor: actor) do
        %{
          id: "booking-#{registration.id}",
          who: registration.name,
          what: registration.course.name,
          balance: registration.balance,
          href: ~p"/admin/courses?#{[booking: registration.id]}" <> "#registration-#{registration.id}"
        }
      end

    {to_collect, to_refund} =
      (order_rows ++ booking_rows)
      |> Enum.sort_by(&Decimal.abs(&1.balance), {:desc, Decimal})
      |> Enum.split_with(&Decimal.positive?(&1.balance))

    Enum.reject(
      [{"collect", ~t"To collect", to_collect}, {"refund", ~t"To refund", to_refund}],
      fn {_key, _title, rows} -> rows == [] end
    )
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

  attr :sales_count, :integer, required: true
  attr :revenue, :any, required: true
  attr :locale, :any, required: true

  defp sales_widget(assigns) do
    ~H"""
    <.widget title={~t"This month"}>
      <dl class="grid grid-cols-2 gap-4 xl:grid-cols-1">
        <div>
          <dt class="text-base-content/65 text-sm">{~t"Sales"}</dt>
          <dd class="text-base-content text-2xl font-semibold tabular-nums">{@sales_count}</dd>
        </div>
        <div>
          <dt class="text-base-content/65 text-sm">{~t"Revenue"}</dt>
          <dd class="text-base-content text-2xl font-semibold tabular-nums">{Format.currency(@revenue, @locale)}</dd>
        </div>
      </dl>
    </.widget>
    """
  end

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
        class="flex items-end gap-2"
      >
        <label class="flex flex-1 flex-col gap-1 text-sm">
          {~t"Month"}
          <input type="month" name="month" value={@month} required class="input w-full" />
        </label>
        <.button type="submit" variant="primary">
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

  attr :balances, :list, required: true, doc: "`{key, title, rows}` groups, largest first"
  attr :locale, :any, required: true
  attr :shown_per_group, :integer, default: 5

  defp balances_widget(assigns) do
    ~H"""
    <.widget id="balances" title={~t"Open balances"}>
      <div class="space-y-4">
        <section :for={{key, title, rows} <- @balances} aria-label={title}>
          <p class="eyebrow text-base-content/65 flex items-baseline justify-between gap-4 pb-1.5">
            <span>{title} · <span class="tabular-nums">{length(rows)}</span></span>
            <span class="tabular-nums">{Format.currency(sum_balances(rows), @locale)}</span>
          </p>
          <ul class="divide-base-content/12 divide-y">
            <.balance_row :for={row <- Enum.take(rows, @shown_per_group)} row={row} locale={@locale} />
          </ul>
          <details
            :if={length(rows) > @shown_per_group}
            id={"balances-more-#{key}"}
            phx-mounted={JS.ignore_attributes(["open"])}
            class="group"
          >
            <summary class="text-primary touch-target flex cursor-pointer list-none items-center py-1 text-sm hover:underline group-open:hidden">
              {~t"Show #{count = length(rows) - @shown_per_group} more"}
            </summary>
            <ul class="divide-base-content/12 border-base-content/12 divide-y border-t">
              <.balance_row :for={row <- Enum.drop(rows, @shown_per_group)} row={row} locale={@locale} />
            </ul>
          </details>
        </section>
      </div>
    </.widget>
    """
  end

  attr :row, :map, required: true
  attr :locale, :any, required: true

  defp balance_row(assigns) do
    ~H"""
    <li id={"balance-#{@row.id}"}>
      <.link
        navigate={@row.href}
        class="-mx-2 flex items-baseline justify-between gap-4 rounded px-2 py-2 transition-colors hover:bg-base-200/50"
      >
        <span class="min-w-0">
          <span class="text-base-content block truncate font-medium">{@row.who}</span>
          <span :if={@row.what} class="text-base-content/65 block truncate text-sm">{@row.what}</span>
        </span>
        <span class="text-base-content shrink-0 tabular-nums">
          {Format.currency(Decimal.abs(@row.balance), @locale)}
        </span>
      </.link>
    </li>
    """
  end

  defp sum_balances(rows), do: rows |> Enum.map(&Decimal.abs(&1.balance)) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :orders, :list, required: true
  attr :overdue, :list, default: [], doc: "orders whose date has passed, listed first and by date"
  attr :empty, :string, required: true
  attr :locale, :any, required: true

  defp day_widget(assigns) do
    ~H"""
    <.widget id={@id} title={@title} count={length(@overdue) + length(@orders)}>
      <div class="space-y-4">
        <section
          :for={{date, orders} <- @overdue |> Enum.group_by(& &1.fulfillment_date) |> Enum.sort_by(&elem(&1, 0), Date)}
          aria-label={~t"Overdue"}
          class="bg-error/5 ring-error/30 pb-1 ring-1"
        >
          <p class="eyebrow text-error-content flex items-center gap-1.5 px-3 pt-2.5 pb-1.5 font-bold">
            <.icon name="hero-exclamation-circle" class="h-4 w-4" />
            {~t"Overdue · #{Format.weekday_day_month(date, @locale)}"}
          </p>
          <ul class="divide-error/15 divide-y">
            <.order_row :for={order <- orders} order={order} hover_class="hover:bg-error/10" />
          </ul>
        </section>

        <section :for={{method, orders} <- by_method(@orders)} aria-label={method_heading(method)}>
          <p class="eyebrow text-base-content/65 px-3 pb-1.5">
            {method_heading(method)} · <span class="tabular-nums">{length(orders)}</span>
          </p>
          <ul class="divide-base-content/8 divide-y">
            <.order_row :for={order <- orders} order={order} hover_class="hover:bg-base-200/60" />
          </ul>
        </section>
      </div>

      <p :if={@overdue == [] and @orders == []} class="text-base-content/65 text-sm">{@empty}</p>
    </.widget>
    """
  end

  attr :order, :map, required: true
  attr :hover_class, :string, required: true

  # What the florist needs to act on, in reading order: whose order, what to make,
  # whether there's a card to write, and how it leaves the shop. Price lives on the
  # order page; it doesn't change what gets made.
  defp order_row(assigns) do
    assigns = assign(assigns, :items, Enum.reject(assigns.order.line_items, & &1.is_card))

    ~H"""
    <li>
      <.link
        navigate={~p"/admin/orders/#{@order.id}"}
        class={["grid-cols-[minmax(0,1fr)_auto] grid items-start gap-x-4 px-3 py-2.5 transition-colors focus-visible:-outline-offset-2", @hover_class]}
      >
        <div class="min-w-0">
          <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
            <span class="text-base-content truncate font-semibold">
              {@order.customer_name || ~t"Unnamed customer"}
            </span>
            <.gift_badge :if={@order.gift} recipient_name={presence(@order.recipient_name)} />
            <.badge :if={present?(@order.card_message)} tone={:warning} icon="hero-pencil-square">
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

          <p
            :if={present?(@order.florist_note)}
            class="text-base-content/85 line-clamp-2 mt-1 text-sm italic"
            data-testid="florist-note"
          >
            <.icon name="hero-chat-bubble-bottom-center-text" class="text-base-content/50 align-[-2px] mr-1 h-3.5 w-3.5" />{@order.florist_note}
          </p>

          <ul class="text-base-content/85 mt-1 space-y-0.5 text-sm">
            <li :for={item <- @items} class="truncate" phx-no-format>
              <span class="text-base-content font-semibold tabular-nums">{item.quantity} ×</span>
              {item.product_name}<span :if={item.variant_size} class="text-base-content/65">, {variant_size_label(item.variant_size)}</span>
            </li>
          </ul>
        </div>

        <div class="flex shrink-0 flex-col items-end gap-0.5 pt-0.5 text-right">
          <.fulfillment_method method={@order.fulfillment_method} class="text-base-content text-sm font-medium" />
          <span
            :if={Format.fulfillment_time(@order, Format.locale())}
            class="text-base-content text-xs tabular-nums"
            data-testid="fulfillment-time"
          >
            {Format.fulfillment_time(@order, Format.locale())}
          </span>
          <span :if={@order.distance_km} class="text-base-content/65 text-xs tabular-nums">
            {@order.distance_km} km
          </span>
        </div>
      </.link>
    </li>
    """
  end

  defp day(date, today) do
    case Date.compare(date, today) do
      :lt -> :overdue
      :eq -> :today
      :gt -> :tomorrow
    end
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

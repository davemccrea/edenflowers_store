defmodule EdenflowersWeb.Admin.OverviewLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Catalog
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
          <:menu>
            <.button navigate={~p"/admin/orders/new"} variant="primary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" /> {~t"New order"}
            </.button>
          </:menu>
        </.admin_page_header>

        <.notifications_offer :if={@vapid_public_key} vapid_public_key={@vapid_public_key} />

        <.attention_widget :if={@attention != []} groups={@attention} locale={@locale} />

        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <section class="admin-card min-w-0 p-4 sm:p-5">
            <.day_section
              id="orders-today"
              title={~t"Today"}
              date={@today}
              orders={@today_orders}
              empty={~t"Nothing to make today"}
              locale={@locale}
            />
            <.day_section
              id="orders-tomorrow"
              title={~t"Tomorrow"}
              date={Date.add(@today, 1)}
              orders={@tomorrow_orders}
              empty={~t"Nothing to make tomorrow"}
              locale={@locale}
              class="border-base-content/12 mt-5 border-t pt-5"
            />
            <div class="border-base-content/12 mt-5 border-t pt-3">
              <.link
                navigate={~p"/admin/orders"}
                class="text-primary touch-target inline-block py-1 text-sm hover:underline"
              >
                {~t"View all orders"} →
              </.link>
            </div>
          </section>
          <aside class="flex min-w-0 flex-col gap-6">
            <.sales_widget sales_count={@sales_count} revenue={@revenue} owed={@owed} locale={@locale} />
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

    today_orders = Map.get(orders_by_day, :today, [])
    tomorrow_orders = Map.get(orders_by_day, :tomorrow, [])
    {owed, to_refund} = actor |> balance_rows() |> Enum.split_with(&Decimal.positive?(&1.amount))
    payment_overdue = Enum.filter(owed, & &1.overdue?)

    attention =
      Enum.reject(
        [
          {"overdue-orders", "hero-clock", ~t"Overdue orders",
           Enum.map(Map.get(orders_by_day, :overdue, []), &overdue_order_row/1)},
          {"failed-subscriptions", "hero-credit-card", ~t"Subscription payment failed",
           Enum.map(Orders.list_failed_subscriptions!(actor: actor), &subscription_row/1)},
          {"refund", "hero-arrow-uturn-left", ~t"To refund", to_refund},
          {"payment-overdue", "hero-banknotes", ~t"Payment overdue", payment_overdue},
          {"sold-out", "hero-archive-box-x-mark", ~t"Sold out",
           Enum.map(Catalog.list_sold_out_variants!(actor: actor), &sold_out_row/1)}
        ],
        fn {_key, _icon, _title, rows} -> rows == [] end
      )

    sales = Orders.sales_summary!(Date.beginning_of_month(today), today, actor: actor)

    socket
    |> assign(:today_orders, today_orders)
    |> assign(:tomorrow_orders, tomorrow_orders)
    |> assign(:attention, attention)
    |> assign(:today, today)
    |> assign(:owed, owed |> Enum.filter(&(&1.kind == :order)) |> sum_amounts())
    |> assign(:sales_count, sales.order_count)
    |> assign(:revenue, sales.revenue)
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

  attr :sales_count, :integer, required: true
  attr :revenue, :any, required: true
  attr :owed, :any, required: true, doc: "what placed orders still owe, overdue or not"
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

  attr :groups, :list, required: true, doc: "`{key, icon, title, rows}`, each with at least one row"
  attr :locale, :any, required: true

  # Collapsed to a line per kind of problem, so it stays short on a phone.
  defp attention_widget(assigns) do
    ~H"""
    <section
      id="attention"
      aria-labelledby="attention-title"
      class="admin-card border-warning/40 bg-warning/5 mb-6 p-4 sm:p-5"
    >
      <h2 id="attention-title" class="text-base-content mb-2 flex items-center gap-2 text-base font-semibold">
        <.icon name="hero-exclamation-triangle" class="text-warning h-5 w-5" />
        {~t"Needs attention"}
      </h2>
      <ul class="divide-warning/20 divide-y">
        <li :for={{key, icon, title, rows} <- @groups}>
          <details id={"attention-#{key}"} phx-mounted={JS.ignore_attributes(["open"])} class="group">
            <summary class="touch-target flex cursor-pointer list-none items-center gap-3 py-2.5">
              <.icon name={icon} class="text-warning-content h-5 w-5 shrink-0" />
              <span class="text-base-content min-w-0 flex-1 font-medium">
                {title} · <span class="tabular-nums">{length(rows)}</span>
              </span>
              <span :if={Map.has_key?(hd(rows), :amount)} class="text-base-content shrink-0 tabular-nums">
                {Format.currency(sum_amounts(rows), @locale)}
              </span>
              <.icon
                name="hero-chevron-down"
                class="text-base-content/50 h-4 w-4 shrink-0 transition-transform group-open:rotate-180"
              />
            </summary>
            <ul class="divide-warning/20 mb-2 ml-8 divide-y">
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
        class="-mx-2 flex items-baseline justify-between gap-4 rounded px-2 py-2 transition-colors hover:bg-base-200/50"
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
  attr :title, :string, required: true
  attr :date, Date, required: true
  attr :orders, :list, required: true
  attr :empty, :string, required: true
  attr :locale, :any, required: true
  attr :class, :any, default: nil

  defp day_section(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-title"} class={@class}>
      <div class="mb-3 flex items-center justify-between gap-3">
        <h2 id={"#{@id}-title"} class="text-base-content text-base font-semibold">
          {@title}
          <span class="text-base-content/65 ml-1 text-sm font-normal">{Format.weekday_day_month(@date, @locale)}</span>
        </h2>
        <.count_badge count={length(@orders)} active={@orders != []} />
      </div>

      <div class="space-y-4">
        <div :for={{method, orders} <- by_method(@orders)} id={"#{@id}-#{method}"}>
          <h3 class="eyebrow text-base-content/65 px-3 pb-1.5">
            {method_heading(method)} · <span class="tabular-nums">{length(orders)}</span>
          </h3>
          <ul class="divide-base-content/8 divide-y">
            <.order_row :for={order <- orders} order={order} />
          </ul>
        </div>
      </div>

      <p :if={@orders == []} class="text-base-content/65 text-sm">{@empty}</p>
    </section>
    """
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
        class="grid-cols-[minmax(0,1fr)_auto] grid items-start gap-x-4 px-3 py-2.5 transition-colors hover:bg-base-200/60 focus-visible:-outline-offset-2"
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
          <span
            :if={Format.fulfillment_time(@order, Format.locale())}
            class="text-base-content text-sm font-medium tabular-nums"
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

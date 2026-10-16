defmodule EdenflowersWeb.Admin.DashboardLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Admin.PushSubscriptions
  alias EdenflowersWeb.Layouts
  alias Edenflowers.Orders
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @timezone "Europe/Helsinki"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: EdenflowersWeb.Endpoint.subscribe("admin:orders")

    {:ok,
     socket
     |> assign(:page_title, ~t"Overview")
     |> assign(:locale, Localize.get_locale())
     |> assign(:vapid_public_key, Edenflowers.WebPush.public_key())
     |> assign_orders()}
  end

  @impl true
  def handle_event("push_subscribed", params, socket),
    do: {:reply, PushSubscriptions.subscribe(params, socket.assigns.current_user), socket}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "admin:orders"}, socket),
    do: {:noreply, assign_orders(socket)}

  defp greeting(%{first_name: first_name}) when is_binary(first_name), do: ~t"Hi, #{first_name}"

  defp greeting(_user), do: ~t"Hi"

  defp assign_orders(socket) do
    actor = socket.assigns.current_user
    open_orders = Orders.list_open_orders!(actor: actor)

    today = @timezone |> DateTime.now!() |> DateTime.to_date()

    sales = Orders.sales_summary!(Date.beginning_of_month(today), today, actor: actor)

    orders_by_date =
      open_orders
      |> Enum.group_by(& &1.fulfillment_date)
      |> Enum.sort_by(fn {date, _} -> date end, Date)

    socket
    |> assign(:orders_by_date, orders_by_date)
    |> assign(:open_order_count, length(open_orders))
    |> assign(:sales_count, sales.order_count)
    |> assign(:revenue, sales.revenue)
    |> assign(:today, today)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={greeting(@current_user)} />

        <.notifications_offer :if={@vapid_public_key} vapid_public_key={@vapid_public_key} />

        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <aside class="flex flex-col gap-6 xl:order-last">
            <.quick_actions />
            <.sales_widget sales_count={@sales_count} revenue={@revenue} locale={@locale} />
          </aside>
          <.orders_widget
            orders_by_date={@orders_by_date}
            open_order_count={@open_order_count}
            today={@today}
            locale={@locale}
          />
        </div>
      </.admin_page>
    </Layouts.admin>
    """
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
      class="bg-base-100 border-base-content/12 mb-6 flex flex-col gap-4 border p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5"
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

  defp quick_actions(assigns) do
    ~H"""
    <.widget id="quick-actions" title={~t"Quick actions"}>
      <div class="grid grid-cols-2 gap-2">
        <.button navigate={~p"/admin/orders/new"} variant="primary" size="sm" class="col-span-2">
          <.icon name="hero-plus" class="h-4 w-4" /> {~t"New order"}
        </.button>
        <.button navigate={~p"/admin/products/new"} variant="neutral" size="sm">{~t"New product"}</.button>
        <.button navigate={~p"/admin/promotions/new"} variant="neutral" size="sm">{~t"New promotion"}</.button>
        <.button navigate={~p"/admin/courses/new"} variant="neutral" size="sm">{~t"New course"}</.button>
        <.button navigate={~p"/admin/fulfillments"} variant="neutral" size="sm">{~t"Calendar"}</.button>
      </div>
    </.widget>
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

  attr :orders_by_date, :list, required: true
  attr :open_order_count, :integer, required: true
  attr :today, :any, required: true
  attr :locale, :any, required: true

  defp orders_widget(assigns) do
    ~H"""
    <.widget title={~t"Upcoming orders"} count={@open_order_count}>
      <div :if={@orders_by_date == []} class="text-base-content/65 flex flex-col items-center gap-2 py-6 text-center">
        <.icon name="hero-check-circle" class="text-base-content/30 h-7 w-7" />
        <p class="text-sm">{~t"No upcoming orders right now"}</p>
      </div>

      <div :if={@orders_by_date != []} class="space-y-3">
        <section
          :for={{date, orders} <- @orders_by_date}
          class={date_group_class(date_group(date, @today))}
        >
          <p class={["eyebrow flex items-center gap-1.5 px-3 pt-2.5 pb-1.5", date_heading_class(date_group(date, @today))]}>
            <span :if={date == @today} aria-hidden="true" class="relative flex h-2 w-2">
              <span class="bg-success/75 absolute inline-flex h-full w-full rounded-full motion-safe:animate-ping" />
              <span class="bg-success relative inline-flex h-2 w-2 rounded-full" />
            </span>
            <.icon :if={date_group(date, @today) == :overdue} name="hero-exclamation-circle" class="h-4 w-4" />
            {format_order_date(date, @today, @locale)}
          </p>
          <ul class={["divide-y", date_divider_class(date_group(date, @today))]}>
            <.order_row :for={order <- orders} order={order} hover_class={date_row_hover_class(date_group(date, @today))} />
          </ul>
        </section>
      </div>

      <div :if={@orders_by_date != []} class="border-base-content/12 mt-4 border-t pt-3">
        <.link navigate={~p"/admin/orders"} class="text-primary inline-block py-1 text-sm hover:underline">
          {~t"View all orders"} →
        </.link>
      </div>
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
            <.gift_badge :if={@order.gift} recipient_name={if present?(@order.recipient_name), do: @order.recipient_name} />
            <.badge :if={present?(@order.card_message)} tone={:warning} icon="hero-pencil-square">
              {~t"Card to write"}
            </.badge>
            <.badge :if={Decimal.positive?(@order.balance)} tone={:warning}>
              <%= if @order.amount_paid do %>
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
          <span :if={@order.distance_km} class="text-base-content/65 text-xs tabular-nums">
            {@order.distance_km} km
          </span>
        </div>
      </.link>
    </li>
    """
  end

  defp present?(nil), do: false
  defp present?(value), do: String.trim(value) != ""

  defp date_group(date, today) do
    case Date.compare(date, today) do
      :lt -> :overdue
      :eq -> :today
      :gt -> :upcoming
    end
  end

  defp date_group_class(:overdue), do: "bg-error/5 ring-error/30 pb-1 ring-1"
  defp date_group_class(:today), do: "bg-success/10 ring-success/30 pb-1 ring-1"
  defp date_group_class(:upcoming), do: nil

  defp date_heading_class(:overdue), do: "text-error-content font-bold"
  defp date_heading_class(:today), do: "text-success-content font-bold"
  defp date_heading_class(:upcoming), do: "text-base-content/65"

  defp date_divider_class(:overdue), do: "divide-error/15"
  defp date_divider_class(:today), do: "divide-success/20"
  defp date_divider_class(:upcoming), do: "divide-base-content/8"

  defp date_row_hover_class(:overdue), do: "hover:bg-error/10"
  defp date_row_hover_class(:today), do: "hover:bg-success/15"
  defp date_row_hover_class(:upcoming), do: "hover:bg-base-200/60"

  defp format_order_date(date, today, locale) do
    cond do
      Date.before?(date, today) -> ~t"Overdue · #{Format.weekday_day_month(date, locale)}"
      date == today -> ~t"Today"
      date == Date.add(today, 1) -> ~t"Tomorrow · #{Format.day_month(date, locale)}"
      true -> Format.weekday_day_month(date, locale)
    end
  end
end

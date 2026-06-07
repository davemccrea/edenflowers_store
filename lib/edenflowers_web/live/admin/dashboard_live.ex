defmodule EdenflowersWeb.Admin.DashboardLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Store.Order
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @timezone "Europe/Helsinki"

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    open_orders = Order.get_all_open!(actor: actor)
    expenses_to_review = Expense.list_needs_review!(actor: actor)

    today = @timezone |> DateTime.now!() |> DateTime.to_date()

    orders_by_date =
      open_orders
      |> Enum.group_by(& &1.fulfillment_date)
      |> Enum.sort_by(fn {date, _} -> date end, Date)

    low_confidence_count =
      Enum.count(expenses_to_review, &(&1.confidence == :low))

    {:ok,
     socket
     |> assign(:page_title, ~t"Dashboard")
     |> assign(:locale, Localize.get_locale())
     |> assign(:orders_by_date, orders_by_date)
     |> assign(:open_order_count, length(open_orders))
     |> assign(:expenses_to_review, expenses_to_review)
     |> assign(:low_confidence_count, low_confidence_count)
     |> assign(:today, today)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="wide">
        <.admin_page_header title={~t"Dashboard"} />

        <div class="space-y-5">
          <.orders_widget
            orders_by_date={@orders_by_date}
            open_order_count={@open_order_count}
            today={@today}
            locale={@locale}
          />
          <.expenses_widget
            expenses_to_review={@expenses_to_review}
            low_confidence_count={@low_confidence_count}
            locale={@locale}
          />
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :orders_by_date, :list, required: true
  attr :open_order_count, :integer, required: true
  attr :today, :any, required: true
  attr :locale, :any, required: true

  defp orders_widget(assigns) do
    ~H"""
    <.widget title={~t"Upcoming Orders"} count={@open_order_count}>
      <div :if={@orders_by_date == []} class="text-base-content/65 flex flex-col items-center gap-2 py-6 text-center">
        <.icon name="hero-check-circle" class="text-base-content/30 h-7 w-7" />
        <p class="text-sm">{~t"No upcoming orders right now"}</p>
      </div>

      <div :if={@orders_by_date != []} class="space-y-3">
        <section
          :for={{date, orders} <- @orders_by_date}
          class={[date == @today && "bg-primary/5 ring-primary/15 rounded-lg pb-1 ring-1"]}
        >
          <p class={["eyebrow flex items-center gap-1.5 px-3 pt-2.5 pb-1.5", if(date == @today, do: "font-bold text-emerald-600", else: "text-base-content/65")]}>
            <span :if={date == @today} aria-hidden="true" class="relative flex h-2 w-2">
              <span class="bg-emerald-500/75 absolute inline-flex h-full w-full rounded-full motion-safe:animate-ping" />
              <span class="relative inline-flex h-2 w-2 rounded-full bg-emerald-500" />
            </span>
            {format_order_date(date, @today, @locale)}
          </p>
          <ul class={["divide-y", if(date == @today, do: "divide-primary/10", else: "divide-base-300/50")]}>
            <.order_row :for={order <- orders} order={order} locale={@locale} />
          </ul>
        </section>
      </div>

      <div :if={@orders_by_date != []} class="border-base-300/70 mt-4 border-t pt-3">
        <.link navigate={~p"/admin/orders"} class="text-primary text-sm hover:underline">
          {~t"View all orders"} →
        </.link>
      </div>
    </.widget>
    """
  end

  attr :order, :map, required: true
  attr :locale, :any, required: true

  defp order_row(assigns) do
    ~H"""
    <li>
      <.link
        navigate={~p"/admin/orders/#{@order.id}"}
        class="grid-cols-[minmax(0,1fr)_auto] grid items-center gap-x-3 px-3 py-2 transition-colors hover:bg-base-200/60 focus-visible:ring-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset"
      >
        <div class="min-w-0">
          <div class="flex min-w-0 items-center gap-2">
            <span class="text-base-content truncate font-medium">{@order.customer_name || "—"}</span>
            <span
              :if={@order.gift}
              class="badge badge-soft badge-sm badge-neutral inline-flex shrink-0 items-center gap-1 whitespace-nowrap"
              title={gift_title(@order)}
            >
              <span aria-hidden="true">🎁</span>
              <span :if={@order.recipient_name} class="max-w-[7rem] truncate">{@order.recipient_name}</span>
              <span :if={is_nil(@order.recipient_name)}>{~t"Gift"}</span>
              <span :if={present?(@order.card_message)} class="sr-only">{~t"— card to write"}</span>
            </span>
          </div>

          <p class="mt-0.5 flex items-center gap-1 text-xs">
            <span aria-hidden="true" class="shrink-0 leading-none">{fulfillment_emoji(@order.fulfillment_method)}</span>
            <span class="text-base-content/65 whitespace-nowrap">{fulfillment_label(@order.fulfillment_method)}</span>
            <span :if={@order.distance_km} aria-hidden="true" class="text-base-content/40">·</span>
            <span :if={@order.distance_km} class="text-base-content/65 whitespace-nowrap tabular-nums">
              {@order.distance_km} km
            </span>
            <span aria-hidden="true" class="text-base-content/40">·</span>
            <span class="text-base-content/85 whitespace-nowrap font-medium">
              {item_count_label(@order.non_card_line_item_count)}
            </span>
          </p>
        </div>

        <span class="text-base-content/65 shrink-0 text-sm tabular-nums">
          {Format.currency(@order.grand_total, @locale)}
        </span>
      </.link>
    </li>
    """
  end

  defp gift_title(%{card_message: msg, recipient_name: name}) do
    base = if name, do: ~t"Gift for #{name}", else: ~t"Gift"
    if present?(msg), do: ~t"#{base} · card to write", else: base
  end

  defp item_count_label(1), do: ~t"1 item"
  defp item_count_label(count), do: ~t"#{count || 0} items"

  defp present?(nil), do: false
  defp present?(value), do: String.trim(value) != ""

  attr :expenses_to_review, :list, required: true
  attr :low_confidence_count, :integer, required: true
  attr :locale, :any, required: true

  defp expenses_widget(assigns) do
    ~H"""
    <.widget title={~t"Unreviewed Expenses"} count={length(@expenses_to_review)}>
      <div :if={@expenses_to_review == []} class="text-base-content/65 flex flex-col items-center gap-2 py-6 text-center">
        <.icon name="hero-check-circle" class="text-base-content/30 h-7 w-7" />
        <p class="text-sm">{~t"All caught up"}</p>
      </div>

      <div :if={@expenses_to_review != []}>
        <div
          :if={@low_confidence_count > 0}
          class="bg-warning/10 border-warning/20 mb-3 flex items-center gap-2 rounded border px-3 py-2 text-sm"
        >
          <.icon name="hero-exclamation-triangle" class="text-warning h-3.5 w-3.5 shrink-0" />
          <span class="text-base-content/85">
            {if @low_confidence_count == 1,
              do: ~t"1 expense needs attention",
              else: ~t"#{@low_confidence_count} expenses need attention"}
          </span>
        </div>

        <ul class="divide-base-300/50 -mx-3 divide-y">
          <li :for={expense <- Enum.take(@expenses_to_review, 5)}>
            <.link
              navigate={~p"/admin/expenses/#{expense.id}"}
              class="flex items-center justify-between gap-3 px-3 py-2 text-sm transition-colors hover:bg-base-200/60 focus-visible:ring-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset"
            >
              <span class="flex min-w-0 items-center gap-2">
                <span
                  :if={expense.confidence == :low}
                  aria-hidden="true"
                  class="bg-warning h-1.5 w-1.5 shrink-0 rounded-full"
                />
                <span class={["text-base-content truncate", expense.confidence == :low && "font-medium"]}>
                  {expense.vendor_name || ~t"Unknown"}
                  <span :if={expense.confidence == :low} class="sr-only">{~t"(low confidence)"}</span>
                </span>
              </span>
              <span class="text-base-content/65 shrink-0 text-sm tabular-nums">
                {Format.amount(expense.total_amount, expense.currency, @locale) || "—"}
              </span>
            </.link>
          </li>
        </ul>

        <div :if={length(@expenses_to_review) > 5} class="text-base-content/65 mt-2 text-xs">
          {~t"+#{length(@expenses_to_review) - 5} more"}
        </div>

        <div class="border-base-300/70 mt-4 border-t pt-3">
          <.link navigate={~p"/admin/expenses"} class="text-primary text-sm hover:underline">
            {~t"Review all"} →
          </.link>
        </div>
      </div>
    </.widget>
    """
  end

  defp fulfillment_emoji(:delivery), do: "🚚"
  defp fulfillment_emoji(:pickup), do: "🛍️"
  defp fulfillment_emoji(_), do: "❓"

  defp fulfillment_label(:delivery), do: ~t"Delivery"
  defp fulfillment_label(:pickup), do: ~t"Pickup"
  defp fulfillment_label(_), do: ~t"Fulfillment method unknown"

  defp format_order_date(date, today, locale) do
    cond do
      date == today -> ~t"Today"
      date == Date.add(today, 1) -> ~t"Tomorrow · #{Format.day_month(date, locale)}"
      true -> Format.weekday_day_month(date, locale)
    end
  end
end

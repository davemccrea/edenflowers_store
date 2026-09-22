defmodule EdenflowersWeb.Admin.DashboardLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Orders
  alias Edenflowers.Expenses
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @timezone "Europe/Helsinki"

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    open_orders = Orders.list_open_orders!(actor: actor)
    expenses_to_review = Expenses.list_expenses_needing_review!(actor: actor)

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
            <.order_row :for={order <- orders} order={order} />
          </ul>
        </section>
      </div>

      <div :if={@orders_by_date != []} class="border-base-300/70 mt-4 border-t pt-3">
        <.link navigate={~p"/admin/orders"} class="text-primary inline-block py-1 text-sm hover:underline">
          {~t"View all orders"} →
        </.link>
      </div>
    </.widget>
    """
  end

  attr :order, :map, required: true

  # What the florist needs to act on, in reading order: whose order, what to make,
  # whether there's a card to write, and how it leaves the shop. Price lives on the
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
            <span
              :if={@order.gift}
              class="badge badge-sm admin-badge-attention inline-flex shrink-0 items-center gap-1 whitespace-nowrap"
            >
              <.icon name="hero-gift" class="h-3.5 w-3.5" />
              <span :if={@order.recipient_name} class="max-w-[9rem] truncate">{~t"For #{@order.recipient_name}"}</span>
              <span :if={is_nil(@order.recipient_name)}>{~t"Gift"}</span>
            </span>
            <span
              :if={present?(@order.card_message)}
              class="badge badge-sm admin-badge-warning inline-flex shrink-0 items-center gap-1 whitespace-nowrap"
            >
              <.icon name="hero-pencil-square" class="h-3.5 w-3.5" />
              {~t"Card to write"}
            </span>
          </div>

          <ul class="text-base-content/85 mt-1 space-y-0.5 text-sm">
            <li :for={item <- @items} class="truncate">
              <span class="text-base-content font-semibold tabular-nums">{item.quantity} ×</span>
              {item.product_name}<span :if={item.variant_size} class="text-base-content/65">, {size_label(item.variant_size)}</span>
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

  defp size_label(size), do: size |> to_string() |> String.capitalize()

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
          class="bg-warning/15 border-warning/40 mb-3 flex items-center gap-2 border px-3 py-2 text-sm"
        >
          <.icon name="hero-exclamation-triangle" class="text-warning-content h-4 w-4 shrink-0" />
          <span class="text-warning-content font-medium">
            {if @low_confidence_count == 1,
              do: ~t"1 expense needs attention",
              else: ~t"#{@low_confidence_count} expenses need attention"}
          </span>
        </div>

        <ul class="divide-base-300/50 -mx-3 divide-y">
          <li :for={expense <- Enum.take(@expenses_to_review, 5)}>
            <.link
              navigate={~p"/admin/expenses/#{expense.id}"}
              class="flex items-center justify-between gap-3 px-3 py-2 text-sm transition-colors hover:bg-base-200/60 focus-visible:-outline-offset-2"
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

        <div class="border-base-300/70 mt-4 border-t pt-2">
          <.link navigate={~p"/admin/expenses"} class="text-primary inline-block py-1 text-sm hover:underline">
            {~t"Review all"} →
          </.link>
        </div>
      </div>
    </.widget>
    """
  end

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
  defp date_divider_class(:upcoming), do: "divide-base-300/50"

  defp format_order_date(date, today, locale) do
    cond do
      Date.before?(date, today) -> ~t"Overdue · #{Format.weekday_day_month(date, locale)}"
      date == today -> ~t"Today"
      date == Date.add(today, 1) -> ~t"Tomorrow · #{Format.day_month(date, locale)}"
      true -> Format.weekday_day_month(date, locale)
    end
  end
end

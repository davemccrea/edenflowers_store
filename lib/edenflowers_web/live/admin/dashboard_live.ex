defmodule EdenflowersWeb.Admin.DashboardLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Store.Order
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Localize.Format

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
     |> assign(:page_title, "Dashboard")
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
        <.admin_page_header title="Dashboard" />

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
    <.widget title="Upcoming Orders" count={@open_order_count}>
      <div :if={@orders_by_date == []} class="py-4 text-center">
        <p class="text-base-content/65 text-sm">No upcoming orders right now</p>
      </div>

      <%!-- A prep worklist, not a grid: one continuous ledger of day-groups.
           Today needs no container — it's first, and its heading carries the
           cue (primary, bold, a leading dot) against the muted future days.
           Rows fill the full width so a one-order day wastes no space. --%>
      <div :if={@orders_by_date != []} class="space-y-3">
        <section :for={{date, orders} <- @orders_by_date}>
          <p class={["eyebrow flex items-center gap-1.5 px-3 pt-2.5 pb-1.5", if(date == @today, do: "text-primary font-bold", else: "text-base-content/65")]}>
            <span :if={date == @today} aria-hidden="true" class="bg-primary h-1.5 w-1.5 rounded-full" />
            {format_order_date(date, @today, @locale)}
          </p>
          <ul class="divide-base-300/50 divide-y">
            <.order_row :for={order <- orders} order={order} locale={@locale} />
          </ul>
        </section>
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
        navigate={~p"/admin/orders"}
        class="grid-cols-[minmax(0,1fr)_auto] grid items-center gap-x-3 px-3 py-2 transition-colors hover:bg-base-200/60 focus-visible:ring-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset"
      >
        <div class="min-w-0">
          <div class="flex min-w-0 items-center gap-2">
            <span class="text-base-content truncate font-medium">{@order.customer_name || "—"}</span>
            <span
              :if={@order.gift}
              class="badge badge-soft badge-xs badge-accent inline-flex shrink-0 items-center gap-1 whitespace-nowrap"
              title={gift_title(@order)}
            >
              <.icon name="hero-gift" class="h-3 w-3" />
              <span :if={@order.recipient_name} class="max-w-[7rem] truncate">{@order.recipient_name}</span>
              <span :if={is_nil(@order.recipient_name)}>Gift</span>
              <.icon :if={present?(@order.card_message)} name="hero-pencil-square" class="h-3 w-3" />
              <span :if={present?(@order.card_message)} class="sr-only">— card to write</span>
            </span>
          </div>

          <p class="text-base-content/65 mt-0.5 flex items-center gap-1 text-xs">
            <.icon name={fulfillment_icon(@order.fulfillment_method)} class="h-3.5 w-3.5 shrink-0" />
            <span class="whitespace-nowrap">{fulfillment_label(@order.fulfillment_method)}</span>
            <span aria-hidden="true" class="text-base-content/40">·</span>
            <span class="whitespace-nowrap">{item_count_label(@order.non_card_line_item_count)}</span>
          </p>
        </div>

        <span class="font-mono text-base-content shrink-0 text-right text-sm tabular-nums">
          {Format.currency(@order.grand_total, @locale)}
        </span>
      </.link>
    </li>
    """
  end

  defp gift_title(%{card_message: msg, recipient_name: name}) do
    base = if name, do: "Gift for #{name}", else: "Gift"
    if present?(msg), do: base <> " · card to write", else: base
  end

  defp item_count_label(1), do: "1 item"
  defp item_count_label(count), do: "#{count || 0} items"

  defp present?(nil), do: false
  defp present?(value), do: String.trim(value) != ""

  attr :expenses_to_review, :list, required: true
  attr :low_confidence_count, :integer, required: true
  attr :locale, :any, required: true

  defp expenses_widget(assigns) do
    ~H"""
    <.widget title="Unreviewed Expenses" count={length(@expenses_to_review)}>
      <div :if={@expenses_to_review == []} class="py-4 text-center">
        <p class="text-base-content/65 text-sm">All caught up</p>
      </div>

      <%!-- A triage queue: the warning leads, rows carry a right-aligned amount column. --%>
      <div :if={@expenses_to_review != []}>
        <div
          :if={@low_confidence_count > 0}
          class="bg-warning/10 border-warning/20 mb-3 flex items-center gap-2 rounded border px-3 py-2 text-sm"
        >
          <.icon name="hero-exclamation-triangle" class="text-warning h-3.5 w-3.5 shrink-0" />
          <span class="text-base-content/80">
            {if @low_confidence_count == 1,
              do: "1 expense needs attention",
              else: "#{@low_confidence_count} expenses need attention"}
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
                  {expense.vendor_name || "Unknown"}
                  <span :if={expense.confidence == :low} class="sr-only">(low confidence)</span>
                </span>
              </span>
              <span class="font-mono text-base-content/65 shrink-0 text-xs tabular-nums">
                {Format.amount(expense.total_amount, expense.currency, @locale)}
              </span>
            </.link>
          </li>
        </ul>

        <div :if={length(@expenses_to_review) > 5} class="text-base-content/65 mt-2 text-xs">
          +{length(@expenses_to_review) - 5} more
        </div>

        <div class="border-base-300/50 mt-4 border-t pt-3">
          <.link navigate={~p"/admin/expenses"} class="text-primary text-sm hover:underline">
            Review all →
          </.link>
        </div>
      </div>
    </.widget>
    """
  end

  defp fulfillment_icon(:delivery), do: "hero-truck"
  defp fulfillment_icon(:pickup), do: "hero-building-storefront"
  defp fulfillment_icon(_), do: "hero-question-mark-circle"

  defp fulfillment_label(:delivery), do: "Delivery"
  defp fulfillment_label(:pickup), do: "Pickup"
  defp fulfillment_label(_), do: "Fulfillment method unknown"

  defp format_order_date(date, today, locale) do
    cond do
      date == today -> "Today · #{Format.day_month(date, locale)}"
      date == Date.add(today, 1) -> "Tomorrow · #{Format.day_month(date, locale)}"
      true -> Format.weekday_day_month(date, locale)
    end
  end
end

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
    unreviewed_expenses = Expense.list_unreviewed!(actor: actor)

    today = @timezone |> DateTime.now!() |> DateTime.to_date()

    orders_by_date =
      open_orders
      |> Enum.group_by(& &1.fulfillment_date)
      |> Enum.sort_by(fn {date, _} -> date end, Date)

    low_confidence_count =
      Enum.count(unreviewed_expenses, &(&1.confidence == :low))

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:locale, Localize.get_locale())
     |> assign(:orders_by_date, orders_by_date)
     |> assign(:open_order_count, length(open_orders))
     |> assign(:unreviewed_expenses, unreviewed_expenses)
     |> assign(:low_confidence_count, low_confidence_count)
     |> assign(:today, today)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path}>
      <.admin_page width="wide">
        <.admin_page_header title="Dashboard" />

        <div class="grid grid-cols-1 items-start gap-5 md:grid-cols-2">
          <.orders_widget orders_by_date={@orders_by_date} open_order_count={@open_order_count} today={@today} />
          <.expenses_widget
            unreviewed_expenses={@unreviewed_expenses}
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

  defp orders_widget(assigns) do
    ~H"""
    <.widget title="Open Orders" count={@open_order_count}>
      <div :if={@orders_by_date == []} class="py-4 text-center">
        <p class="text-sm text-base-content/40">No open orders right now</p>
      </div>

      <%!-- A schedule, not a list: a left rule threads the date groups into an agenda. --%>
      <ol :if={@orders_by_date != []} class="relative space-y-5 border-l border-base-300/70 pl-5">
        <li :for={{date, orders} <- @orders_by_date} class="relative">
          <span class={[
            "absolute -left-[1.4rem] top-1 h-2 w-2 rounded-full ring-4 ring-base-100",
            if(date == @today, do: "bg-primary", else: "bg-base-300")
          ]} />
          <p class={[
            "eyebrow mb-1.5",
            if(date == @today, do: "text-primary", else: "text-base-content/40")
          ]}>
            {format_order_date(date, @today)}
          </p>
          <ul class="space-y-1.5">
            <li :for={order <- orders} class="flex items-baseline justify-between gap-3 text-sm">
              <span class="text-base-content truncate">{order.customer_name || "—"}</span>
              <span class="text-base-content/40 font-mono text-xs shrink-0">{order.order_reference}</span>
            </li>
          </ul>
        </li>
      </ol>
    </.widget>
    """
  end

  attr :unreviewed_expenses, :list, required: true
  attr :low_confidence_count, :integer, required: true
  attr :locale, :any, required: true

  defp expenses_widget(assigns) do
    ~H"""
    <.widget title="Unreviewed Expenses" count={length(@unreviewed_expenses)}>
      <div :if={@unreviewed_expenses == []} class="py-4 text-center">
        <p class="text-sm text-base-content/40">All caught up</p>
      </div>

      <%!-- A triage queue: the warning leads, rows carry a right-aligned amount column. --%>
      <div :if={@unreviewed_expenses != []}>
        <div
          :if={@low_confidence_count > 0}
          class="mb-3 flex items-center gap-2 rounded bg-warning/10 border border-warning/20 px-3 py-2 text-sm"
        >
          <.icon name="hero-exclamation-triangle" class="h-3.5 w-3.5 shrink-0 text-warning" />
          <span class="text-base-content/80">
            {if @low_confidence_count == 1,
              do: "1 expense needs attention",
              else: "#{@low_confidence_count} expenses need attention"}
          </span>
        </div>

        <ul class="divide-y divide-base-300/50">
          <li
            :for={expense <- Enum.take(@unreviewed_expenses, 5)}
            class="flex items-center justify-between gap-3 py-2 text-sm first:pt-0"
          >
            <span class="flex min-w-0 items-center gap-2">
              <span
                :if={expense.confidence == :low}
                class="h-1.5 w-1.5 shrink-0 rounded-full bg-warning"
                title="Low confidence"
              />
              <span class={[
                "truncate text-base-content",
                expense.confidence == :low && "font-medium"
              ]}>
                {expense.vendor_name || "Unknown"}
              </span>
            </span>
            <span class="shrink-0 font-mono text-xs tabular-nums text-base-content/55">
              {Format.amount(expense.total_amount, expense.currency, @locale)}
            </span>
          </li>
        </ul>

        <div :if={length(@unreviewed_expenses) > 5} class="mt-2 text-xs text-base-content/35">
          +{length(@unreviewed_expenses) - 5} more
        </div>

        <div class="mt-4 pt-3 border-t border-base-300/50">
          <.link navigate={~p"/admin/expenses"} class="text-sm text-primary hover:underline">
            Review all →
          </.link>
        </div>
      </div>
    </.widget>
    """
  end

  defp format_order_date(date, today) do
    cond do
      date == today -> "Today · #{Calendar.strftime(date, "%d %b")}"
      date == Date.add(today, 1) -> "Tomorrow · #{Calendar.strftime(date, "%d %b")}"
      true -> Calendar.strftime(date, "%A · %d %b")
    end
  end
end

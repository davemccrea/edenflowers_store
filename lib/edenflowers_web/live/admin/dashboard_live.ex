defmodule EdenflowersWeb.Admin.DashboardLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Store.Order
  alias Edenflowers.Expenses.Expense

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
      <div class="px-8 py-8 max-w-4xl">
        <.admin_page_header title="Dashboard" />

        <div class="grid grid-cols-1 gap-5 md:grid-cols-2">
          <.orders_widget orders_by_date={@orders_by_date} open_order_count={@open_order_count} today={@today} />
          <.expenses_widget unreviewed_expenses={@unreviewed_expenses} low_confidence_count={@low_confidence_count} />
        </div>
      </div>
    </Layouts.admin>
    """
  end

  attr :orders_by_date, :list, required: true
  attr :open_order_count, :integer, required: true
  attr :today, :any, required: true

  defp orders_widget(assigns) do
    ~H"""
    <div class="bg-base-200 border border-base-300/60 rounded-lg p-5">
      <div class="flex items-start justify-between mb-4">
        <h2 class="text-base font-semibold text-base-content">Open Orders</h2>
        <.count_badge count={@open_order_count} active={@open_order_count > 0} />
      </div>

      <div :if={@orders_by_date == []} class="py-4 text-center">
        <p class="text-sm text-base-content/40">No open orders right now</p>
      </div>

      <div :if={@orders_by_date != []} class="space-y-4">
        <div :for={{date, orders} <- @orders_by_date}>
          <p class="eyebrow text-base-content/40 mb-1.5">
            {format_order_date(date, @today)}
          </p>
          <ul class="space-y-1.5">
            <li :for={order <- orders} class="flex items-center justify-between text-sm">
              <span class="text-base-content">{order.customer_name || "—"}</span>
              <span class="text-base-content/40 font-mono text-xs">{order.order_reference}</span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :unreviewed_expenses, :list, required: true
  attr :low_confidence_count, :integer, required: true

  defp expenses_widget(assigns) do
    ~H"""
    <div class="bg-base-200 border border-base-300/60 rounded-lg p-5">
      <div class="flex items-start justify-between mb-4">
        <h2 class="text-base font-semibold text-base-content">Unreviewed Expenses</h2>
        <.count_badge count={length(@unreviewed_expenses)} active={length(@unreviewed_expenses) > 0} />
      </div>

      <div :if={@unreviewed_expenses == []} class="py-4 text-center">
        <p class="text-sm text-base-content/40">All caught up</p>
      </div>

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

        <ul class="space-y-1.5">
          <li
            :for={expense <- Enum.take(@unreviewed_expenses, 5)}
            class="flex items-center justify-between text-sm"
          >
            <span class={[
              "text-base-content",
              expense.confidence == :low && "text-warning font-medium"
            ]}>
              {expense.vendor_name || "Unknown"}
            </span>
            <span class="text-base-content/40 tabular-nums text-xs">
              {expense.total_amount} {expense.currency |> to_string() |> String.upcase()}
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
    </div>
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

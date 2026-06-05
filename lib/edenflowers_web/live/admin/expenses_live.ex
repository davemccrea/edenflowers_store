defmodule EdenflowersWeb.Admin.ExpensesLive do
  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Expenses.Expense

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Expenses")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path}>
      <div class="container mx-auto py-10">
        <header class="mb-8">
          <p class="eyebrow text-base-content/55 mb-2">Finance</p>
          <h1 class="page-title">Expenses</h1>
        </header>

        <Cinder.collection
          id="expenses-table"
          resource={Expense}
          actor={@current_user}
          click={fn expense -> JS.navigate(~p"/admin/expenses/#{expense.id}") end}
        >
          <:col :let={expense} field="date" sort label="Date">
            {expense.date}
          </:col>
          <:col :let={expense} field="vendor_name" label="Vendor">
            {expense.vendor_name}
          </:col>
          <:col :let={expense} field="total_amount" sort label="Amount">
            {expense.total_amount} {expense.currency}
          </:col>
          <:col :let={expense} field="category" filter label="Category">
            {expense.category}
          </:col>
          <:col :let={expense} field="confidence" filter label="Confidence">
            {expense.confidence}
          </:col>
          <:col :let={expense} field="reviewed_at" label="Reviewed">
            {if expense.reviewed_at, do: "✓", else: ""}
          </:col>
        </Cinder.collection>
      </div>
    </Layouts.admin>
    """
  end
end

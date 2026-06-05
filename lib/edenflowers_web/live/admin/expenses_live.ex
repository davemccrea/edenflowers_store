defmodule EdenflowersWeb.Admin.ExpensesLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

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
      <.admin_page width="full">
        <.admin_page_header title="Expenses" />

        <Cinder.collection
          id="expenses-table"
          resource={Expense}
          actor={@current_user}
          theme="daisy_ui"
          click={fn expense -> JS.navigate(~p"/admin/expenses/#{expense.id}") end}
        >
          <:col :let={expense} field="date" sort label="Date">
            <span class="tabular-nums whitespace-nowrap">
              {Calendar.strftime(expense.date, "%d %b %Y")}
            </span>
          </:col>
          <:col :let={expense} field="vendor_name" label="Vendor">
            <span class="font-medium">{expense.vendor_name || "—"}</span>
          </:col>
          <:col :let={expense} field="total_amount" sort label="Amount">
            <span class="tabular-nums whitespace-nowrap">
              {expense.total_amount} {expense.currency |> to_string() |> String.upcase()}
            </span>
          </:col>
          <:col :let={expense} field="category" filter label="Category">
            {format_category(expense.category)}
          </:col>
          <:col :let={expense} field="confidence" filter label="Confidence">
            <.confidence_badge confidence={expense.confidence} />
          </:col>
          <:col :let={expense} field="reviewed_at" label="Reviewed">
            <span :if={expense.reviewed_at} class="badge badge-soft badge-success badge-sm">
              Reviewed
            </span>
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp format_category(nil), do: "—"
  defp format_category(cat) do
    cat |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end
end

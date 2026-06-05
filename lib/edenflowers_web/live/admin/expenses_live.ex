defmodule EdenflowersWeb.Admin.ExpensesLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Localize.Format

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Expenses")
     |> assign(:locale, Localize.get_locale())}
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
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn expense -> JS.navigate(~p"/admin/expenses/#{expense.id}") end}
        >
          <:col :let={expense} field="date" sort label="Date">
            <span class="tabular-nums whitespace-nowrap">
              {Format.date(expense.date, @locale)}
            </span>
          </:col>
          <:col :let={expense} field="vendor_name" label="Vendor">
            <span class="font-medium">{expense.vendor_name || "—"}</span>
          </:col>
          <:col :let={expense} field="total_amount" sort label="Amount">
            <span class="tabular-nums whitespace-nowrap">
              {Format.amount(expense.total_amount, expense.currency, @locale)}
            </span>
          </:col>
          <:col :let={expense} field="category" filter label="Category">
            {format_category(expense.category)}
          </:col>
          <:col :let={expense} field="confidence" filter label="Confidence">
            <.confidence_badge confidence={expense.confidence} />
          </:col>
          <:col :let={expense} field="reviewed_at" label="Reviewed">
            <span :if={expense.reviewed_at} class="inline-flex" title="Reviewed">
              <.icon name="hero-check" class="h-4 w-4 text-base-content" />
              <span class="sr-only">Reviewed</span>
            </span>
            <span :if={is_nil(expense.reviewed_at)} class="text-base-content/30" aria-hidden="true">
              —
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

defmodule EdenflowersWeb.Admin.ExpensesLive do
  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Expenses")
     |> assign(:locale, Localize.get_locale())}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="full">
        <.admin_page_header title={~t"Expenses"} />

        <Cinder.collection
          id="expenses-table"
          resource={Expense}
          actor={@current_user}
          theme={EdenflowersWeb.Admin.CinderTheme}
          url_state={@url_state}
          show_filters={:toggle}
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          click={fn expense -> JS.navigate(~p"/admin/expenses/#{expense.id}") end}
        >
          <:col :let={expense} field="date" sort label={~t"Date"}>
            <span class="whitespace-nowrap tabular-nums">
              {Format.date(expense.date, @locale) || "—"}
            </span>
          </:col>
          <:col :let={expense} field="vendor_name" label={~t"Vendor"}>
            <span class="font-medium">{expense.vendor_name || "—"}</span>
          </:col>
          <:col :let={expense} field="total_amount" sort label={~t"Amount"}>
            <span class="whitespace-nowrap tabular-nums">
              {Format.amount(expense.total_amount, expense.currency, @locale) || "—"}
            </span>
          </:col>
          <:col
            :let={expense}
            field="category"
            filter={[type: :select, label: ~t"Category", prompt: ~t"All"]}
          >
            <.category_badge category={expense.category} />
          </:col>
          <:col
            :let={expense}
            field="confidence"
            filter={[type: :select, label: ~t"Confidence", prompt: ~t"All"]}
          >
            <.confidence_badge confidence={expense.confidence} />
          </:col>
          <:col :let={expense} field="reviewed_at" label={~t"Reviewed"}>
            <span :if={expense.reviewed_at} class="inline-flex" title={~t"Reviewed"}>
              <.icon name="hero-check" class="text-base-content h-4 w-4" />
              <span class="sr-only">{~t"Reviewed"}</span>
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
end

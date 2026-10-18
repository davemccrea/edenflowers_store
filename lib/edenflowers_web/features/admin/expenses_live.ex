defmodule EdenflowersWeb.Admin.ExpensesLive do
  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Format
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Expenses")
     |> assign(:locale, Localize.get_locale())
     |> assign(:report_month, previous_month())}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Expenses"}>
          <:actions>
            <.button type="button" size="sm" variant="neutral" phx-click={JS.exec("phx-show", to: "#export-drawer")}>
              <.icon name="hero-arrow-down-tray" class="h-4 w-4" />
              {~t"Export"}
            </.button>
            <.button
              href={Edenflowers.External.PapraAPI.documents_url()}
              target="_blank"
              rel="noopener"
              variant="neutral"
              size="sm"
            >
              {~t"Open Papra"}
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
            </.button>
          </:actions>
        </.admin_page_header>

        <.drawer
          id="export-drawer"
          placement="right"
          label={~t"Export"}
          class="bg-base-100 border-base-content/12 w-[88vw] flex h-full flex-col border-l sm:w-96"
        >
          <header class="flex items-center justify-between gap-4 p-4">
            <h2 class="text-lg font-semibold">{~t"Export"}</h2>
            <.icon_button
              phx-click={JS.exec("phx-hide", to: "#export-drawer")}
              size="sm"
              aria_label={~t"Close"}
            >
              <.icon name="hero-x-mark" class="h-5 w-5" />
            </.icon_button>
          </header>
          <form action={~p"/admin/accounting"} method="get" class="flex flex-col gap-4 p-4">
            <label class="flex flex-col gap-1 text-sm">
              {~t"Month"}
              <input type="month" name="month" value={@report_month} required class="input w-full" />
            </label>
            <.button type="submit">
              <.icon name="hero-arrow-down-tray" class="h-4 w-4" />
              {~t"Download"}
            </.button>
          </form>
        </.drawer>

        <Cinder.collection
          id="expenses-table"
          resource={Expense}
          action={:admin_list}
          actor={@current_user}
          search={[
            label: ~t"Expense",
            placeholder: ~t"Search vendor or description…",
            fn: &search_expenses/3
          ]}
          url_state={@url_state}
          show_filters={:toggle}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn expense -> JS.navigate(~p"/admin/expenses/#{expense.id}") end}
        >
          <:col :let={expense} field="vendor_name" search sort label={~t"Vendor"}>
            <.link
              navigate={~p"/admin/expenses/#{expense.id}"}
              class="max-w-28 inline-block truncate align-middle font-medium hover:underline sm:max-w-none"
            >
              {expense.vendor_name || ~t"Unknown vendor"}
            </.link>
          </:col>
          <:col :let={expense} field="date" sort={[cycle: [nil, :desc, :asc]]} label={~t"Date"} class="max-sm:hidden">
            <span :if={expense.date} class="whitespace-nowrap tabular-nums">
              {Format.date(expense.date, @locale)}
            </span>
            <.blank :if={is_nil(expense.date)} />
          </:col>
          <:col :let={expense} field="total_amount" sort label={~t"Amount"} class="text-right">
            <span :if={expense.total_amount && expense.currency} class="whitespace-nowrap tabular-nums">
              {Format.currency_in(expense.total_amount, expense.currency, @locale)}
            </span>
            <.blank :if={is_nil(expense.total_amount) or is_nil(expense.currency)} />
          </:col>
          <:col
            :let={expense}
            field="confidence"
            sort
            filter={[type: :select, label: ~t"Confidence", prompt: ~t"All", options: confidence_options()]}
            label={~t"Confidence"}
            class="max-sm:hidden"
          >
            <.confidence_badge confidence={expense.confidence} />
          </:col>
          <:col
            :let={expense}
            field="reviewed"
            sort
            filter={[
              type: :boolean,
              label: ~t"Review",
              labels: %{true: ~t"Reviewed", false: ~t"Not reviewed"}
            ]}
            label={~t"Reviewed"}
          >
            <span :if={expense.reviewed_at}>
              <.icon name="hero-check" class="h-4 w-4" />
              <span class="sr-only">{~t"Reviewed"}</span>
            </span>
            <.blank :if={is_nil(expense.reviewed_at)} />
          </:col>
          <:col
            :let={expense}
            field="category"
            sort
            filter={[type: :select, label: ~t"Category", prompt: ~t"All", options: category_options()]}
            label={~t"Category"}
            class="max-sm:hidden"
          >
            <.category_badge category={expense.category} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp previous_month do
    Edenflowers.ShopTime.today()
    |> Date.beginning_of_month()
    |> Date.add(-1)
    |> Date.to_iso8601()
    |> String.slice(0, 7)
  end

  defp search_expenses(query, _searchable_columns, search_term) do
    require Ash.Query
    import Ash.Expr

    case_insensitive_term = Ash.CiString.new(search_term)

    Ash.Query.filter(
      query,
      expr(
        contains(vendor_name, ^case_insensitive_term) or
          contains(description, ^case_insensitive_term)
      )
    )
  end
end

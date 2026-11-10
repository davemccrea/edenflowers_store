defmodule EdenflowersWeb.Admin.ExpensesLive do
  @moduledoc """
  Admin list of expenses imported from Papra.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Events
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Format
  alias EdenflowersWeb.Admin.PubSub
  alias EdenflowersWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe([Events.admin_expenses()])

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
      <.admin_page>
        <.admin_page_header title={~t"Expenses"}>
          <:actions>
            <.button
              href={Edenflowers.External.PapraAPI.documents_url()}
              target="_blank"
              rel="noopener"
              variant="secondary"
              size="sm"
            >
              {~t"Open Papra"}
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
            </.button>
          </:actions>
        </.admin_page_header>

        <Cinder.collection
          id="expenses-table"
          resource={Expense}
          action={:admin_list}
          actor={@current_user}
          query_opts={[load: [:overdue, :scheduled, :needs_review]]}
          search={[
            label: ~t"Search",
            placeholder: ~t"Search vendor or description…",
            fn: &search_expenses/3
          ]}
          url_state={@url_state}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn expense -> JS.navigate(~p"/admin/expenses/#{expense.id}") end}
        >
          <:filter
            field="needs_review"
            type={:select}
            label={~t"Review"}
            prompt={~t"All"}
            options={[{~t"Needs review", true}, {~t"Reviewed", false}]}
          />
          <:col :let={expense} field="vendor_name" search sort label={~t"Vendor"}>
            <.link
              navigate={~p"/admin/expenses/#{expense.id}"}
              class="max-w-28 inline-block truncate align-middle font-semibold hover:underline sm:max-w-none"
            >
              {expense.vendor_name || ~t"Unknown vendor"}
            </.link>
            <.badge
              :if={expense.needs_review}
              tone={:attention}
              class="align-middle max-sm:mt-1 max-sm:flex max-sm:w-fit sm:ml-1"
            >
              {~t"Needs review"}
            </.badge>
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
            field="paid"
            sort
            filter={[
              type: :select,
              label: ~t"Payment",
              prompt: ~t"All",
              options: [{~t"Paid or scheduled", true}, {~t"Unpaid", false}]
            ]}
            label={~t"Paid"}
          >
            <.expense_payment_status expense={expense} locale={@locale} />
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

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket),
    do: {:noreply, PubSub.schedule_refresh(socket, :expenses_table)}

  def handle_info({:admin_refresh, :expenses_table}, socket),
    do: {:noreply, Cinder.refresh_table(socket, "expenses-table")}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp search_expenses(query, _searchable_columns, search_term) do
    require Ash.Query
    term = Ash.CiString.new(search_term)
    Ash.Query.filter(query, matches?(term: ^term))
  end
end

defmodule EdenflowersWeb.Admin.ExpensesLive do
  @moduledoc """
  Admin list of expenses imported from Papra.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Bank
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.External.EnableBankingAPI
  alias Edenflowers.Format
  alias EdenflowersWeb.Admin.BankController
  alias EdenflowersWeb.Layouts

  require Logger

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: EdenflowersWeb.Endpoint.subscribe("admin:expenses")

    {:ok,
     socket
     |> assign(:page_title, ~t"Expenses")
     |> assign(:locale, Localize.get_locale())
     |> assign(:bank_connection, bank_connection(socket.assigns.current_user))}
  end

  # Only production can reach the bank, so elsewhere there's nothing to connect.
  defp bank_connection(actor) do
    if EnableBankingAPI.configured?() do
      {:ok, connection} = Bank.current_bank_connection(actor: actor, load: [:expired, :renewal_due])
      {:configured, connection}
    else
      :not_configured
    end
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

        <.bank_status
          :if={@bank_connection != :not_configured}
          connection={elem(@bank_connection, 1)}
          locale={@locale}
        />

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

  attr :connection, :any, required: true
  attr :locale, :any, required: true

  defp bank_status(assigns) do
    ~H"""
    <div id="bank-status" role="status" class="mb-4 flex flex-wrap items-center gap-x-3 gap-y-2 text-sm">
      <%= cond do %>
        <% is_nil(@connection) -> %>
          <.badge tone={:neutral} icon="hero-building-library">{~t"Bank not connected"}</.badge>
          <span class="text-base-content/75">
            {~t"Connect it to mark payments paid as they leave or arrive."}
          </span>
        <% @connection.expired -> %>
          <.badge tone={:error} icon="hero-building-library">{~t"Bank disconnected"}</.badge>
          <span>
            {~t"The connection ended on #{date = Format.date(@connection.valid_until, @locale)}. Connect again to keep payments up to date."}
          </span>
        <% @connection.renewal_due -> %>
          <.badge tone={:warning} icon="hero-building-library">{~t"Bank connection ending"}</.badge>
          <span>
            {~t"It ends on #{date = Format.date(@connection.valid_until, @locale)}. Connect again to keep payments up to date."}
          </span>
        <% true -> %>
          <.badge tone={:success} icon="hero-building-library">{~t"Bank connected"}</.badge>
          <span class="text-base-content/75">
            {~t"Until #{date = Format.date(@connection.valid_until, @locale)}"}
          </span>
      <% end %>
      <.button phx-click="connect_bank" variant="secondary" size="sm">
        {if @connection, do: ~t"Reconnect", else: ~t"Connect bank"}
      </.button>
    </div>
    """
  end

  @impl true
  def handle_event("connect_bank", _params, socket) do
    user = socket.assigns.current_user
    state = BankController.sign_state(user)

    case Bank.bank_authorization_url(state, url(~p"/admin/bank/callback"), actor: user) do
      {:ok, url} ->
        {:noreply, redirect(socket, external: url)}

      {:error, error} ->
        Logger.error("Starting a bank connection failed: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"The bank couldn't be reached. Please try again.")}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "admin:expenses"}, socket),
    do: {:noreply, Cinder.refresh_table(socket, "expenses-table")}

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

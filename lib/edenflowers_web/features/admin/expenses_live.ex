defmodule EdenflowersWeb.Admin.ExpensesLive do
  @moduledoc """
  Admin list of expenses imported from Papra, under the bank payments that
  have no receipt in it yet.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Bank
  alias Edenflowers.Events
  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Format
  alias EdenflowersWeb.Admin.PubSub
  alias EdenflowersWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe([Events.admin_expenses(), Events.admin_bank()])

    {:ok,
     socket
     |> assign(:page_title, ~t"Expenses")
     |> assign(:locale, Localize.get_locale())
     |> assign(:linking, nil)
     |> assign(:candidates, [])
     |> load_bank_payments()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :highlighted_payment_id, params["payment"])
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

        <.missing_receipts
          :if={@missing != [] or @dismissed != []}
          missing={@missing}
          dismissed={@dismissed}
          linking={@linking}
          candidates={@candidates}
          highlighted={@highlighted_payment_id}
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
          <:col :let={expense} field="date" sort={[cycle: [nil, :asc]]} label={~t"Date"} class="max-sm:hidden">
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

  attr :missing, :list, required: true
  attr :dismissed, :list, required: true
  attr :linking, :any, required: true, doc: "the id of the payment whose expense picker is open, or nil"
  attr :candidates, :list, required: true
  attr :highlighted, :string, required: true, doc: "the id of the payment a link from the Overview was for, or nil"
  attr :locale, :any, required: true

  defp missing_receipts(assigns) do
    # Hiding only one or two expenses behind a link saves no room.
    shown = if length(assigns.candidates) <= 7, do: 7, else: 5
    {first_candidates, more_candidates} = Enum.split(assigns.candidates, shown)
    assigns = assign(assigns, first_candidates: first_candidates, more_candidates: more_candidates)

    ~H"""
    <section
      id="missing-receipts"
      aria-labelledby="missing-receipts-title"
      class={["admin-card mb-6 p-4 sm:p-5", @missing != [] && "shadow-[inset_4px_0_0_var(--color-warning)]"]}
    >
      <h2 id="missing-receipts-title" class="text-base-content mb-2 flex items-center gap-1.5 text-base font-semibold">
        {~t"Bank payments without a receipt"}
        <.count_badge :if={@missing != []} count={length(@missing)} active={true} tone={:warning} />
        <%!-- A tap-opened popover rather than a hover tooltip, since Jennie works on her phone. --%>
        <.icon_button
          popovertarget="missing-receipts-help"
          style="anchor-name: --missing-receipts-help"
          size="sm"
          aria_label={~t"How payments get their receipt"}
        >
          <.icon name="hero-information-circle" class="text-base-content/60 h-5 w-5" />
        </.icon_button>
      </h2>
      <div
        id="missing-receipts-help"
        popover
        style="position-anchor: --missing-receipts-help"
        class="dropdown bg-base-100 border-base-content/12 text-base-content/75 rounded-box mt-2 max-w-xs border p-3 text-sm font-normal shadow"
      >
        {~t"Upload the missing receipt to Papra. If its amount matches and it was paid within a week of the payment, it links itself at the next bank sync, within six hours. Otherwise, link it here."}
      </div>
      <p :if={@missing == []} class="text-base-content/75 text-sm">
        {~t"Nothing missing for payments over a week old."}
      </p>
      <ul class="divide-base-content/12 divide-y text-sm">
        <li
          :for={payment <- @missing}
          id={"bank-payment-#{payment.id}"}
          aria-current={payment.id == @highlighted && "true"}
          class={["scroll-mt-[calc(env(safe-area-inset-top)+6rem)] py-3", payment.id == @highlighted && "row-flash"]}
        >
          <div class="flex items-baseline justify-between gap-4">
            <span class="min-w-0">
              <span class="text-base-content block truncate font-semibold">
                {payment.counterparty || ~t"Unknown payee"}
              </span>
              <span class="text-base-content/75 block break-words">
                {Format.date(payment.booked_on, @locale)}<span :if={payment.reference_number}> · {~t"ref. #{reference = payment.reference_number}"}</span><span :if={
                  payment.message
                }> · {payment.message}</span>
              </span>
            </span>
            <span class="text-base-content shrink-0 tabular-nums">
              {Format.currency_in(payment.amount, payment.currency, @locale)}
            </span>
          </div>
          <div class="mt-2 flex flex-wrap gap-2">
            <.button
              phx-click="choose_expense"
              phx-value-id={payment.id}
              aria-expanded={to_string(@linking == payment.id)}
              aria-controls={@linking == payment.id && "linkable-expenses"}
              variant="secondary"
              size="sm"
            >
              <.icon name="hero-link" class="h-4 w-4" /> {~t"Link to expense"}
            </.button>
            <.button phx-click="dismiss" phx-value-id={payment.id} variant="ghost" size="sm">
              {~t"No receipt needed"}
            </.button>
          </div>
          <div :if={@linking == payment.id} id="linkable-expenses" class="mt-3">
            <p :if={@candidates == []} role="status" class="text-base-content/75">
              {~t"No unlinked expenses are dated within 30 days of this payment."}
            </p>
            <p :if={@candidates != []} class="text-base-content/75 mb-1">
              {~t"Closest amount first. An unpaid expense you choose becomes paid on #{date = Format.date(payment.booked_on, @locale)}."}
            </p>
            <ul class="border-base-content/12 divide-base-content/12 divide-y border-l pl-3">
              <.linkable_expense
                :for={{expense, index} <- Enum.with_index(@first_candidates)}
                expense={expense}
                best={index == 0}
                locale={@locale}
              />
            </ul>
            <details
              :if={@more_candidates != []}
              id="more-linkable-expenses"
              phx-mounted={JS.ignore_attributes(["open"])}
              class="group"
            >
              <summary class="link-underline-hover text-base-content/75 touch-target inline-block cursor-pointer list-none py-2 pl-3 group-open:hidden">
                {~t"Show #{count = length(@more_candidates)} more"}
              </summary>
              <ul class="border-base-content/12 divide-base-content/12 divide-y border-l pl-3">
                <.linkable_expense :for={expense <- @more_candidates} expense={expense} best={false} locale={@locale} />
              </ul>
            </details>
          </div>
        </li>
      </ul>
      <details
        :if={@dismissed != []}
        id="dismissed-bank-payments"
        phx-mounted={JS.ignore_attributes(["open"])}
        class="mt-2 text-sm"
      >
        <summary class="text-base-content/75 touch-target cursor-pointer py-2">
          {~t"#{count = length(@dismissed)} need no receipt"}
        </summary>
        <ul class="divide-base-content/12 divide-y">
          <li
            :for={payment <- @dismissed}
            id={"dismissed-bank-payment-#{payment.id}"}
            class="flex items-center justify-between gap-4 py-2"
          >
            <span class="min-w-0">
              <span class="text-base-content block truncate">{payment.counterparty || ~t"Unknown payee"}</span>
              <span class="text-base-content/75 block break-words">
                {Format.date(payment.booked_on, @locale)}<span :if={payment.message}> · {payment.message}</span>
              </span>
            </span>
            <span class="flex shrink-0 items-center gap-3">
              <span class="tabular-nums">{Format.currency_in(payment.amount, payment.currency, @locale)}</span>
              <.button phx-click="restore" phx-value-id={payment.id} variant="ghost" size="sm">
                {~t"Restore"}
              </.button>
            </span>
          </li>
        </ul>
      </details>
    </section>
    """
  end

  attr :expense, :map, required: true, doc: "an expense from the linkable_by_hand read"
  attr :best, :boolean, required: true, doc: "the closest amount, offered as the primary choice"
  attr :locale, :any, required: true

  defp linkable_expense(assigns) do
    ~H"""
    <li id={"linkable-expense-#{@expense.id}"} class="flex items-center justify-between gap-4 py-2">
      <span class="min-w-0">
        <span class="flex min-w-0 items-center gap-1.5">
          <span class="text-base-content truncate font-semibold">{@expense.vendor_name || ~t"Unknown vendor"}</span>
          <.badge :if={@expense.same_amount?} tone={:tag} class="shrink-0">{~t"Same amount"}</.badge>
        </span>
        <span class="text-base-content/75 mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1">
          <span class="tabular-nums">{Format.date(@expense.date, @locale)}</span>
          <span :if={@expense.paid_on && !@expense.scheduled} class="whitespace-nowrap tabular-nums">
            {~t"paid #{date = Format.date(@expense.paid_on, @locale)}"}
          </span>
          <.expense_payment_status :if={is_nil(@expense.paid_on) or @expense.scheduled} expense={@expense} locale={@locale} />
          <span :if={@expense.reference_number} class="break-all">
            {~t"ref. #{reference = @expense.reference_number}"}
          </span>
        </span>
      </span>
      <span class="flex shrink-0 items-center gap-3">
        <span class="tabular-nums">{Format.currency_in(@expense.total_amount, @expense.currency, @locale)}</span>
        <.button
          phx-click="link"
          phx-value-expense={@expense.id}
          variant={if @best, do: "primary", else: "secondary"}
          size="sm"
          aria-label={
            ~t"Choose #{vendor = @expense.vendor_name || ~t"Unknown vendor"}, #{amount = Format.currency_in(@expense.total_amount, @expense.currency, @locale)}, #{date = Format.date(@expense.date, @locale)}"
          }
        >
          {~t"Choose"}
        </.button>
      </span>
    </li>
    """
  end

  @impl true
  def handle_event("choose_expense", %{"id" => id}, socket) do
    if socket.assigns.linking == id do
      {:noreply, assign(socket, linking: nil, candidates: [])}
    else
      payment = Enum.find(socket.assigns.missing, &(&1.id == id))

      candidates =
        Expenses.expenses_linkable_by_hand!(payment.booked_on, payment.amount, payment.currency,
          actor: socket.assigns.current_user
        )

      {:noreply, assign(socket, linking: id, candidates: candidates)}
    end
  end

  def handle_event("link", %{"expense" => expense_id}, socket) do
    with %{} = payment <- Enum.find(socket.assigns.missing, &(&1.id == socket.assigns.linking)),
         %{} = expense <- Enum.find(socket.assigns.candidates, &(&1.id == expense_id)),
         {:ok, _expense} <-
           Expenses.link_expense_bank_payment(expense, payment.booked_on, payment.bank_id,
             actor: socket.assigns.current_user
           ) do
      {:noreply, socket |> load_bank_payments() |> put_flash(:success, ~t"Payment linked to its expense.")}
    else
      _not_linked -> {:noreply, socket |> load_bank_payments() |> put_flash(:error, ~t"The payment wasn't linked.")}
    end
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    payment = Enum.find(socket.assigns.missing, &(&1.id == id))
    {:noreply, socket |> update_payment(&Bank.dismiss_bank_payment/2, payment, ~t"Marked as needing no receipt.")}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    payment = Enum.find(socket.assigns.dismissed, &(&1.id == id))

    {:noreply,
     socket |> update_payment(&Bank.restore_bank_payment/2, payment, ~t"Back among the payments without a receipt.")}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket),
    do: {:noreply, PubSub.schedule_refresh(socket, :expenses_table)}

  def handle_info({:admin_refresh, :expenses_table}, socket),
    do: {:noreply, socket |> load_bank_payments() |> Cinder.refresh_table("expenses-table")}

  def handle_info(_message, socket), do: {:noreply, socket}

  # Gone from the list since the page last loaded, as another tab handled it.
  defp update_payment(socket, _action, nil, _done), do: load_bank_payments(socket)

  defp update_payment(socket, action, payment, done) do
    case action.(payment, actor: socket.assigns.current_user) do
      {:ok, _payment} -> socket |> load_bank_payments() |> put_flash(:success, done)
      {:error, _} -> put_flash(socket, :error, ~t"The payment wasn't updated.")
    end
  end

  # Closes the expense picker when its payment has left the list.
  defp load_bank_payments(socket) do
    actor = socket.assigns.current_user
    missing = Bank.bank_payments_missing_receipt!(actor: actor)
    linking = Enum.find_value(missing, &(&1.id == socket.assigns.linking && &1.id))

    socket
    |> assign(:missing, missing)
    |> assign(:dismissed, Bank.dismissed_bank_payments!(actor: actor))
    |> assign(:linking, linking)
    |> assign(:candidates, if(linking, do: socket.assigns.candidates, else: []))
  end

  defp search_expenses(query, _searchable_columns, search_term) do
    require Ash.Query
    term = Ash.CiString.new(search_term)
    Ash.Query.filter(query, matches?(term: ^term))
  end
end

defmodule EdenflowersWeb.Admin.InvoiceLive do
  @moduledoc "Standalone invoice drafting and issued document management."
  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}
  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.Drawers

  alias Edenflowers.Format
  alias Edenflowers.Locales
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Changes.IssueInvoice
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoiceFinancials
  alias Edenflowers.Pricing
  alias Edenflowers.ShopTime
  alias EdenflowersWeb.Admin.EmailDrawer
  alias EdenflowersWeb.Admin.InvoiceLog
  alias EdenflowersWeb.Admin.InvoicesLive
  alias EdenflowersWeb.Layouts

  @customer_fields ~w(buyer_name buyer_email buyer_address business_customer company_name business_id billing_address locale)
  @load [
    :editable?,
    :status,
    :buyer,
    :overdue?,
    :amount_paid,
    :amount_unpaid,
    :sendable?,
    :cancellable?,
    :paper_trail_versions,
    payments: [:undoable?],
    credit_note: [:invoice, :paper_trail_versions]
  ]
  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       locale: Localize.get_locale(),
       error: nil,
       submitted: false,
       issue_attempted: false,
       customer_search_empty?: false,
       email_form: nil,
       email_kind: nil,
       preview: nil,
       log: [],
       tax_rates: Pricing.list_selectable_tax_rates!(actor: socket.assigns.current_user)
     )}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    case Payments.get_invoice(id, actor: socket.assigns.current_user, load: @load) do
      {:ok, invoice} -> {:noreply, show_invoice(socket, invoice)}
      _ -> {:noreply, socket |> put_flash(:error, ~t"Invoice not found.") |> push_navigate(to: ~p"/admin/invoices")}
    end
  end

  def handle_params(_params, _uri, socket) do
    form =
      Invoice
      |> AshPhoenix.Form.for_create(
        :create,
        form_opts(socket, %{
          "invoice_date" => Date.to_iso8601(ShopTime.today()),
          "due_date" => Date.to_iso8601(Invoice.default_due_date()),
          "locale" => Locales.default(),
          "business_customer" => "false"
        })
      )
      |> AshPhoenix.Form.add_form(:lines, params: empty_line(socket.assigns.tax_rates), validate?: false)

    {:noreply, socket |> assign(invoice: nil, page_title: ~t"New invoice", editable: true) |> put_form(form)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={@page_title} back={{~t"Invoices", ~p"/admin/invoices"}} sticky={@editable}>
          <:subtitle :if={!@editable}>
            <.badge tone={InvoicesLive.status_tone(@invoice.status, @invoice.overdue?)}>
              {InvoicesLive.status_label(@invoice.status, @invoice.overdue?)}
            </.badge>
            <.badge :if={@invoice.sendable? && is_nil(@invoice.sent_at)} tone={:neutral}>{~t"Not sent"}</.badge>
            <.badge :if={@invoice.status == :open} href="#invoice-totals" tone={:warning} class="tabular-nums xl:hidden">
              {~t"To collect #{amount = Format.currency(@invoice.amount_unpaid, @locale)}"}
              <.icon name="hero-arrow-down" class="h-3 w-3" />
            </.badge>
          </:subtitle>
          <:actions>
            <.button
              :if={@editable}
              type="submit"
              form="invoice-form"
              variant="secondary"
              size="sm"
              class="max-sm:btn-square"
              aria-label={~t"Save draft"}
            >
              <.icon name="hero-document-check" class="h-4 w-4 sm:hidden" />
              <span class="max-sm:sr-only">{~t"Save draft"}</span>
            </.button>
            <.button
              :if={@editable}
              type="submit"
              form="invoice-form"
              name="intent"
              value="issue"
              variant="primary"
              size="sm"
              data-confirm={~t"Issue this invoice? Its number, buyer details and amounts will be frozen."}
            >{~t"Issue invoice"}</.button>
            <.button
              :if={!@editable}
              href={~p"/admin/invoices/#{@invoice.id}/pdf"}
              target="_blank"
              rel="noopener"
              variant="secondary"
              size="sm"
            >{~t"Download PDF"}</.button>
          </:actions>
        </.admin_page_header>
        <p :if={@error} id="invoice-error" role="alert" class="text-error mb-5 whitespace-pre-line">{@error}</p>
        <.email_drawer
          :if={!@editable}
          form={@email_form}
          preview={@preview}
          swedish_toggle?={@invoice.locale != "sv-FI"}
          {EmailDrawer.text(@email_kind, email_record(@email_kind, @invoice), @locale)}
        />
        <.form
          :if={@editable}
          for={@form}
          id="invoice-form"
          phx-auto-recover="recover"
          novalidate
          phx-change="validate"
          phx-submit="save"
          data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
          class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start"
        >
          <div class="min-w-0 space-y-6">
            <.form_section title={~t"Customer"}>
              <.customer_picker field={@form[:previous_invoice_id]} empty?={@customer_search_empty?} />
              <div class="grid gap-4 sm:grid-cols-2">
                <.input
                  field={@form[:buyer_name]}
                  label={~t"Name"}
                  class="input w-full"
                  autocomplete="off"
                  autocapitalize="words"
                />
                <.input
                  field={@form[:buyer_email]}
                  type="email"
                  label={~t"Email"}
                  class="input w-full"
                  autocomplete="off"
                />
              </div>
              <div class="mt-4">
                <.input field={@form[:business_customer]} type="checkbox" label={~t"Business customer"} />
              </div>
              <div :if={@form[:business_customer].value not in [true, "true"]} class="mt-4">
                <.input
                  field={@form[:buyer_address]}
                  type="textarea"
                  label={~t"Postal address"}
                  class="textarea w-full"
                  rows="3"
                />
              </div>
              <.input :if={@form[:business_customer].value in [true, "true"]} field={@form[:buyer_address]} type="hidden" />
              <div :if={@form[:business_customer].value in [true, "true"]} class="mt-4 grid gap-4 sm:grid-cols-2">
                <.input field={@form[:company_name]} label={~t"Company name"} class="input w-full" />
                <.input field={@form[:business_id]} label={~t"Y-tunnus"} class="input w-full" />
                <div class="sm:col-span-2">
                  <.input
                    field={@form[:billing_address]}
                    type="textarea"
                    label={~t"Billing address"}
                    class="textarea w-full"
                    rows="3"
                  />
                </div>
              </div>
            </.form_section>
            <.form_section title={~t"Items"}>
              <:description>{~t"Prices include VAT."}</:description>
              <div class="space-y-5">
                <.inputs_for :let={line_form} field={@form[:lines]}>
                  <fieldset
                    id={"invoice-line-#{line_form.index}"}
                    class="border-base-content/12 border-b pb-5 last:border-0"
                  >
                    <legend class="sr-only">{~t"Item"} {line_form.index + 1}</legend>
                    <div class="flex items-start gap-3">
                      <div class="min-w-0 flex-1">
                        <.input
                          field={line_form[:description]}
                          id={"line-#{line_form.index}-description"}
                          label={~t"Description"}
                          class="input w-full"
                        />
                      </div>
                      <.button
                        type="button"
                        phx-click="remove_line"
                        phx-value-path={line_form.name}
                        variant="ghost"
                        size="sm"
                        class="btn-square mt-6 shrink-0"
                        aria-label={~t"Remove item #{number = line_form.index + 1}"}
                      >
                        <.icon name="hero-trash" class="h-4 w-4" />
                      </.button>
                    </div>
                    <div class="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
                      <.input
                        field={line_form[:quantity]}
                        value={decimal_comma(line_form[:quantity].value)}
                        id={"line-#{line_form.index}-quantity"}
                        label={~t"Qty"}
                        inputmode="decimal"
                        class="input w-full tabular-nums"
                      />
                      <.input
                        field={line_form[:unit_price]}
                        value={decimal_comma(line_form[:unit_price].value)}
                        id={"line-#{line_form.index}-price"}
                        label={~t"Price each (€)"}
                        inputmode="decimal"
                        class="input w-full tabular-nums"
                      />
                      <div class="col-span-2 sm:col-span-1">
                        <.input
                          field={line_form[:vat_rate]}
                          id={"line-#{line_form.index}-vat"}
                          type="select"
                          label={~t"VAT"}
                          value={normalize_decimal(line_form[:vat_rate].value)}
                          options={vat_options(@tax_rates, line_form[:vat_rate].value, @locale)}
                          class="select w-full"
                        />
                      </div>
                    </div>
                  </fieldset>
                </.inputs_for>
              </div>
              <.button type="button" phx-click="add_line" variant="secondary" size="sm"><.icon
                name="hero-plus"
                class="h-4 w-4"
              /> {~t"Add item"}</.button>
            </.form_section>
          </div>
          <aside class="min-w-0 space-y-6">
            <.form_section title={~t"Invoice details"}>
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@form[:invoice_date]} type="date" label={~t"Invoice date"} class="input w-full" required />
                <.input field={@form[:due_date]} type="date" label={~t"Due date"} class="input w-full" required />
                <div class="sm:col-span-2">
                  <.input
                    field={@form[:locale]}
                    type="select"
                    label={~t"Language"}
                    options={Enum.map(Locales.all(), &{Locales.name(&1), &1})}
                    class="select w-full"
                  />
                </div>
              </div>
              <details
                id="invoice-additional-details"
                class="mt-5"
                open={additional_details?(@form)}
                phx-mounted={JS.ignore_attributes(["open"])}
              >
                <summary class="link link-primary cursor-pointer text-sm">{~t"Additional details (optional)"}</summary>
                <div class="mt-4 space-y-4">
                  <.input field={@form[:customer_reference]} label={~t"Customer reference (optional)"} class="input w-full" />
                  <.input
                    field={@form[:supply_date]}
                    type="date"
                    label={~t"Supply / advance date (optional)"}
                    class="input w-full"
                  />
                  <.input
                    field={@form[:supply_description]}
                    label={~t"Supply / advance details (optional)"}
                    class="input w-full"
                  />
                </div>
              </details>
            </.form_section>
            <.totals snapshot={@totals_preview} locale={@locale} draft show_errors={@submitted} />
          </aside>
        </.form>
        <div :if={@editable && @invoice} class="mt-6">
          <.invoice_history log={@log} locale={@locale} />
        </div>
        <div :if={!@editable} class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <div class="min-w-0 space-y-6">
            <.widget title={@invoice.buyer}>
              <div class="break-words">
                <p>{@invoice.buyer_email}</p>
                <p class="mt-2 whitespace-pre-line">
                  {if @invoice.business_customer, do: @invoice.billing_address, else: @invoice.buyer_address}
                </p>
                <p :if={@invoice.business_customer} class="mt-2">{@invoice.business_id}</p>
                <p :if={@invoice.supply_date} class="mt-2">
                  {~t"Supply / advance date"}: {Format.date(@invoice.supply_date, @locale)}
                </p>
                <p :if={@invoice.supply_description} class="mt-2">{@invoice.supply_description}</p>
                <p :if={@invoice.customer_reference} class="mt-2">
                  {~t"Customer reference"}: {@invoice.customer_reference}
                </p>
              </div>
              <dl class="mt-5 grid grid-cols-2 gap-4">
                <div>
                  <dt class="text-base-content/75 text-sm">{~t"Invoice date"}</dt><dd class="tabular-nums">
                    {Format.date(@invoice.invoice_date, @locale)}
                  </dd>
                </div>
                <div>
                  <dt class="text-base-content/75 text-sm">{~t"Due date"}</dt><dd class={["tabular-nums", @invoice.overdue? && "text-error font-semibold"]}>
                    {Format.date(@invoice.due_date, @locale)}
                  </dd>
                </div>
              </dl>
            </.widget>
            <.widget title={~t"Items"}>
              <dl class="divide-base-content/12 divide-y">
                <div :for={line <- @invoice.financial_snapshot["lines"]} class="flex justify-between gap-4 py-3">
                  <div class="min-w-0 break-words">
                    <dt>{line["description"]}</dt><dd class="text-base-content/75 text-sm tabular-nums">
                      {line["quantity"]} × {Format.currency(Decimal.new(line["unit_price"]), @locale)} · {~t"VAT"} {line[
                        "vat_rate"
                      ]}%
                    </dd>
                  </div>
                  <dd class="shrink-0 tabular-nums">{Format.currency(Decimal.new(line["gross"]), @locale)}</dd>
                </div>
              </dl>
            </.widget>
            <.totals snapshot={{:ok, @invoice.financial_snapshot}} locale={@locale} invoice={@invoice} />
          </div>
          <aside class="min-w-0 space-y-6">
            <.widget :if={@invoice.sendable?} title={~t"Email invoice"}>
              <p class="text-base-content/75 mb-4 break-words text-sm">{@invoice.buyer_email}</p>
              <p :if={@invoice.sent_at} class="mb-4 text-sm">
                {~t"Last sent"}: {Format.datetime(@invoice.sent_at, @locale)}
              </p>
              <.button type="button" phx-click="open_email" phx-value-kind="invoice" variant="primary" size="sm">
                <.icon name="hero-envelope" class="h-4 w-4" />
                {if @invoice.overdue?,
                  do: ~t"Send reminder",
                  else: if(@invoice.sent_at, do: ~t"Resend invoice", else: ~t"Send invoice")}
              </.button>
            </.widget>
            <.widget title={~t"Bank transfers"}>
              <p :if={@invoice.payments == []} class="text-base-content/75">{~t"No payments recorded."}</p>
              <ul class="divide-base-content/12 divide-y">
                <li
                  :for={payment <- Enum.sort_by(@invoice.payments, & &1.paid_at, {:desc, DateTime})}
                  class="flex flex-wrap items-center justify-between gap-3 py-3"
                >
                  <span class="tabular-nums">
                    {Format.date(payment.paid_at, @locale)} · {Format.currency(payment.amount, @locale)}
                    <span :if={payment.reverses_payment_id}>{~t"Reversal"}</span>
                  </span>
                  <.button
                    :if={payment.undoable? && @invoice.status != :cancelled}
                    type="button"
                    phx-click="undo_payment"
                    phx-value-id={payment.id}
                    variant="secondary"
                    size="sm"
                    data-confirm={~t"Reverse this mistaken payment entry? Its history will be preserved."}
                  >{~t"Reverse payment"}</.button>
                </li>
              </ul>
              <.form
                :if={@invoice.status == :open}
                for={@payment_form}
                id="invoice-payment-form"
                novalidate
                phx-change="validate_payment"
                phx-submit="record_payment"
                class="scroll-mt-[calc(env(safe-area-inset-top)+6rem)] mt-5 space-y-4"
              >
                <.input
                  field={@payment_form[:amount]}
                  value={@payment_form.source.raw_params["amount"]}
                  label={~t"Amount (€)"}
                  inputmode="decimal"
                  class="input w-full tabular-nums"
                  required
                />
                <.input field={@payment_form[:paid_on]} type="date" label={~t"Payment date"} class="input w-full" required />
                <.button type="submit" variant="primary">{~t"Record bank transfer"}</.button>
              </.form>
              <p
                :if={@invoice.status in [:open, :paid] && !@invoice.cancellable?}
                id="accountant-correction"
                class="text-base-content/75 mt-4 text-sm"
              >
                {~t"For corrections to a paid or partly paid invoice, contact the accountant."}
              </p>
            </.widget>
            <details
              :if={@invoice.cancellable?}
              id="invoice-corrections"
              class="admin-card p-4 sm:p-5"
              phx-mounted={JS.ignore_attributes(["open"])}
            >
              <summary class="cursor-pointer text-base font-semibold">{~t"Correct this invoice"}</summary>
              <.form
                for={@credit_form}
                id="invoice-credit-form"
                phx-change="validate_credit"
                phx-submit="credit"
                class="mt-4 space-y-4"
              >
                <p>{~t"A full credit note reverses this unpaid invoice and its VAT."}</p>
                <.input
                  field={@credit_form[:reason]}
                  type="textarea"
                  label={~t"Reason (optional)"}
                  class="textarea w-full"
                  rows="2"
                />
                <.button
                  type="submit"
                  variant="destructive"
                  data-confirm={~t"Credit the entire unpaid invoice? This cannot be undone."}
                >{~t"Issue full credit note"}</.button>
              </.form>
            </details>
            <.widget :if={@invoice.credit_note} title={~t"Credit note"}>
              <div :if={@invoice.credit_note} class="flex flex-wrap items-center gap-3">
                <p class="w-full">
                  {~t"Credit note"} {@invoice.credit_note.number} · {Format.date(@invoice.credit_note.credit_date, @locale)}
                </p>
                <.button
                  href={~p"/admin/credit-notes/#{@invoice.credit_note.id}"}
                  target="_blank"
                  rel="noopener"
                  variant="secondary"
                  size="sm"
                >{~t"Download credit note"}</.button>
                <.button type="button" phx-click="open_email" phx-value-kind="credit_note" variant="primary" size="sm">
                  <.icon name="hero-envelope" class="h-4 w-4" /> {~t"Send credit note"}
                </.button>
              </div>
            </.widget>
            <.invoice_history log={@log} locale={@locale} />
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :log, :list, required: true
  attr :locale, :string, required: true

  defp invoice_history(assigns) do
    ~H"""
    <.widget id="invoice-log" title={~t"History"}>
      <ol class="divide-base-content/12 divide-y text-sm">
        <.history_entry
          :for={{entry, index} <- Enum.with_index(@log)}
          id={"invoice-log-entry-#{index}"}
          title={entry.title}
          at={entry.at}
          locale={@locale}
        >
          <:details :if={entry.details != []}>
            <dl class="border-base-content/12 mt-1.5 mb-1 ml-0.5 space-y-2 border-l pl-3">
              <div :for={{label, value} <- entry.details}>
                <dt :if={label} class="text-base-content/75 text-xs">{label}</dt>
                <dd class="text-base-content/85 whitespace-pre-line break-words">{value}</dd>
              </div>
            </dl>
          </:details>
        </.history_entry>
      </ol>
    </.widget>
    """
  end

  attr :invoice, :any, default: nil
  attr :snapshot, :any, required: true
  attr :locale, :string, required: true
  attr :draft, :boolean, default: false
  attr :show_errors, :boolean, default: true

  defp totals(assigns) do
    ~H"""
    <.widget
      id="invoice-totals"
      title={if @draft, do: ~t"Draft totals", else: ~t"Invoice totals"}
      class="scroll-mt-[calc(env(safe-area-inset-top)+6rem)]"
    >
      <%= case @snapshot do %>
        <% {:ok, snapshot} -> %>
          <dl class="space-y-3 tabular-nums">
            <div :for={row <- snapshot["vat_breakdown"]} class="flex flex-wrap justify-between gap-x-6 gap-y-1">
              <dt>{~t"VAT"} {row["rate"]}%</dt>
              <dd>
                {~t"Net"} {Format.currency(Decimal.new(row["base"]), @locale)} · {~t"VAT"} {Format.currency(
                  Decimal.new(row["vat"]),
                  @locale
                )}
              </dd>
            </div>
            <.money_row
              label={~t"Total incl. VAT"}
              amount={Decimal.new(snapshot["gross"])}
              locale={@locale}
              strong={is_nil(@invoice)}
              ruled={!is_nil(@invoice)}
            />
            <.money_row
              :if={@invoice && Decimal.positive?(@invoice.amount_paid)}
              label={~t"Paid"}
              amount={Decimal.negate(@invoice.amount_paid)}
              locale={@locale}
            />
            <.money_row
              :if={@invoice && @invoice.status in [:open, :paid]}
              label={~t"Balance"}
              amount={@invoice.amount_unpaid}
              locale={@locale}
              strong
            />
          </dl>
          <.button
            :if={@invoice && @invoice.status == :open}
            href="#invoice-payment-form"
            variant="secondary"
            size="sm"
            class="mt-4"
          >
            <.icon name="hero-banknotes" class="h-4 w-4" /> {~t"Record payment"}
          </.button>
        <% {:error, message} -> %>
          <p role="status" class="text-base-content/75">
            {if @show_errors, do: message, else: ~t"Complete the items to see the total."}
          </p>
      <% end %>
    </.widget>
    """
  end

  def handle_event("live_select_change", %{"id" => "customer-select", "text" => term}, socket) do
    term = String.trim(term)

    customers =
      if term == "",
        do: [],
        else: Payments.search_invoice_customers!(term, actor: socket.assigns.current_user, query: [limit: 10])

    options = Enum.map(customers, &{"#{&1.buyer} · #{&1.buyer_email}", &1.id})
    send_update(LiveSelect.Component, id: "customer-select", options: options)
    {:noreply, assign(socket, customer_search_empty?: term != "" && customers == [])}
  end

  def handle_event("validate", %{"invoice" => params}, socket) do
    params = prefill_customer(params, socket.assigns)
    {:noreply, socket |> assign(error: nil) |> validate_form(params)}
  end

  def handle_event("recover", %{"invoice" => params}, socket),
    do: {:noreply, socket |> assign(error: nil) |> validate_form(params)}

  def handle_event("validate_payment", %{"payment" => params}, socket),
    do:
      {:noreply,
       assign(socket, payment_form: AshPhoenix.Form.validate(socket.assigns.payment_form, params), error: nil)}

  def handle_event("open_email", %{"kind" => kind}, socket) when kind in ["invoice", "credit_note"] do
    record = email_record(String.to_existing_atom(kind), socket.assigns.invoice)

    if record && (kind == "credit_note" || socket.assigns.invoice.sendable? == true),
      do: {:noreply, EmailDrawer.open(socket, kind, record)},
      else: {:noreply, socket}
  end

  def handle_event("close_email", _params, socket), do: {:noreply, EmailDrawer.close(socket)}

  def handle_event("validate_email", %{"email" => params}, %{assigns: %{email_form: form}} = socket)
      when not is_nil(form),
      do:
        {:noreply,
         EmailDrawer.validate(socket, params, email_record(socket.assigns.email_kind, socket.assigns.invoice))}

  def handle_event("validate_credit", %{"credit" => params}, socket),
    do: {:noreply, assign(socket, credit_form: to_form(params, as: :credit), error: nil)}

  def handle_event("add_line", _params, socket) do
    params = empty_line(socket.assigns.tax_rates)
    {:noreply, put_form(socket, AshPhoenix.Form.add_form(socket.assigns.form, :lines, params: params))}
  end

  def handle_event("remove_line", %{"path" => path}, socket),
    do: {:noreply, put_form(socket, AshPhoenix.Form.remove_form(socket.assigns.form, path))}

  def handle_event("save", %{"invoice" => params} = input, socket) do
    params = used_params(params)
    socket = assign(socket, submitted: true, issue_attempted: input["intent"] == "issue")
    result = AshPhoenix.Form.submit(socket.assigns.form, params: params)

    socket =
      case result do
        {:ok, draft} -> assign(socket, :invoice, draft)
        {:error, form} -> put_form(socket, form)
      end

    intent = input["intent"]

    result =
      case result do
        {:ok, draft} when intent == "issue" ->
          Payments.issue_invoice(draft, actor: socket.assigns.current_user)

        result ->
          result
      end

    case result do
      {:ok, invoice} ->
        message = if invoice.issued_at, do: ~t"Invoice issued. It is ready to email.", else: ~t"Draft saved."

        {:noreply,
         socket
         |> assign(error: nil)
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/admin/invoices/#{invoice.id}")}

      {:error, %Phoenix.HTML.Form{}} ->
        {:noreply, assign(socket, error: ~t"Check the fields marked below and try again.")}

      {:error, _issue_error} ->
        {:noreply,
         socket
         |> put_form(socket |> draft_form(socket.assigns.invoice) |> AshPhoenix.Form.validate(params))
         |> assign(error: ~t"Check the fields marked below and try again.")}
    end
  end

  def handle_event("send_email", %{"email" => params}, %{assigns: %{email_form: form, preview: preview}} = socket)
      when not is_nil(form) and not is_nil(preview) do
    %{invoice: invoice, email_kind: kind, current_user: actor} = socket.assigns

    result =
      case kind do
        :invoice -> Payments.send_invoice(invoice, Map.take(params, ["message"]), actor: actor)
        :credit_note -> Payments.send_credit_note(invoice.credit_note, Map.take(params, ["message"]), actor: actor)
      end

    case result do
      {:ok, _} ->
        message = if kind == :invoice, do: ~t"Invoice emailed.", else: ~t"Credit note emailed."
        {:noreply, socket |> EmailDrawer.close() |> refresh() |> put_flash(:info, message)}

      {:error, _} ->
        message =
          if kind == :invoice,
            do: ~t"Could not email the invoice. It remains issued; try sending again.",
            else: ~t"Could not email the credit note. Try again in a moment."

        {:noreply, socket |> EmailDrawer.validate(params, email_record(kind, invoice)) |> put_flash(:error, message)}
    end
  end

  def handle_event("send_email", _params, socket), do: {:noreply, socket}

  def handle_event("record_payment", %{"payment" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.payment_form, params: used_params(params)) do
      {:ok, _invoice} ->
        finish(socket, {:ok, nil}, ~t"Bank transfer recorded.")

      {:error, form} ->
        {:noreply, assign(socket, payment_form: form, error: ~t"Check the fields marked below and try again.")}
    end
  end

  def handle_event("undo_payment", %{"id" => id}, socket),
    do:
      finish(
        socket,
        Payments.undo_invoice_payment(socket.assigns.invoice, id, actor: socket.assigns.current_user),
        ~t"Payment reversed."
      )

  def handle_event("credit", %{"credit" => params}, socket) do
    socket = assign(socket, credit_form: to_form(params, as: :credit))

    finish(
      socket,
      Payments.cancel_invoice(params |> Map.take(["reason"]) |> Map.put("invoice_id", socket.assigns.invoice.id),
        actor: socket.assigns.current_user
      ),
      ~t"Credit note issued."
    )
  end

  defp finish(socket, {:ok, _}, message), do: {:noreply, socket |> refresh() |> put_flash(:info, message)}

  defp finish(socket, {:error, _error}, _),
    do:
      {:noreply,
       assign(socket,
         error: ~t"Check the entered values and try again."
       )}

  defp refresh(socket),
    do:
      show_invoice(
        socket,
        Payments.get_invoice!(socket.assigns.invoice.id, actor: socket.assigns.current_user, load: @load)
      )

  defp show_invoice(socket, invoice) do
    socket
    |> assign(
      invoice: invoice,
      log: InvoiceLog.entries(invoice, socket.assigns.locale),
      editable: invoice.editable?,
      error: nil,
      page_title: if(invoice.number, do: ~t"Invoice #{number = invoice.number}", else: ~t"Invoice draft"),
      email_form: nil,
      email_kind: nil,
      preview: nil,
      credit_form: to_form(%{"reason" => ""}, as: :credit),
      submitted: false,
      issue_attempted: false,
      payment_form: payment_form(invoice, socket.assigns.current_user)
    )
    |> put_form(draft_form(socket, invoice))
  end

  defp form_opts(socket, params) do
    [as: "invoice", actor: socket.assigns.current_user, params: params, forms: [auto?: true]]
  end

  defp draft_form(socket, invoice), do: AshPhoenix.Form.for_update(invoice, :update_draft, form_opts(socket, %{}))

  defp validate_form(socket, params), do: put_form(socket, AshPhoenix.Form.validate(socket.assigns.form, params))

  defp put_form(socket, %Phoenix.HTML.Form{source: form}), do: put_form(socket, form)

  # After a failed issue, the fields issuing needs stay marked as Jennie corrects them.
  defp put_form(socket, form) do
    form =
      if socket.assigns.issue_attempted do
        form.source
        |> Ash.Changeset.apply_attributes(force?: true)
        |> elem(1)
        |> IssueInvoice.field_errors()
        |> Enum.reduce(form, &AshPhoenix.Form.add_error(&2, &1))
      else
        form
      end

    assign(socket, form: to_form(form), totals_preview: totals_preview(form.source))
  end

  defp totals_preview(changeset) do
    if Enum.any?(changeset.errors, &(Map.get(&1, :field) == :lines or match?([:lines | _], Map.get(&1, :path)))),
      do: {:error, ~t"Complete the items to see the total."},
      else: InvoiceFinancials.build(Ash.Changeset.get_attribute(changeset, :lines))
  end

  defp additional_details?(form),
    do: Enum.any?([:customer_reference, :supply_date, :supply_description], &(form[&1].value not in [nil, ""]))

  defp email_record(nil, _invoice), do: nil
  defp email_record(:invoice, invoice), do: invoice
  defp email_record(:credit_note, nil), do: nil
  defp email_record(:credit_note, invoice), do: invoice.credit_note

  defp prefill_customer(%{"previous_invoice_id" => id} = params, assigns) when id not in [nil, ""] do
    if id == assigns.form[:previous_invoice_id].value do
      params
    else
      case Payments.get_invoice(id, actor: assigns.current_user) do
        {:ok, %{sent_at: sent_at} = previous} when not is_nil(sent_at) ->
          Map.merge(params, customer_params(previous))

        _ ->
          params
      end
    end
  end

  defp prefill_customer(params, _assigns), do: params

  defp customer_params(previous) do
    Map.new(@customer_fields, fn field ->
      {field, form_value(Map.get(previous, String.to_existing_atom(field)))}
    end)
  end

  defp vat_options(tax_rates, current, locale) do
    options =
      Enum.map(tax_rates, fn rate ->
        {"#{rate.name} (#{Format.percentage(rate.percentage, locale)})",
         rate.percentage |> Decimal.mult(100) |> Decimal.normalize() |> Decimal.to_string(:normal)}
      end)

    current = normalize_decimal(current)

    if current in [nil, ""] or Enum.any?(options, fn {_label, value} -> value == current end),
      do: options,
      else: options ++ [{"#{current}%", current}]
  end

  defp payment_form(invoice, actor) do
    invoice
    |> AshPhoenix.Form.for_update(:record_payment,
      as: "payment",
      actor: actor,
      params: %{
        "amount" => Decimal.to_string(invoice.amount_unpaid, :normal),
        "paid_on" => Date.to_iso8601(ShopTime.today())
      },
      transform_params: fn params, _type -> payment_params(params) end,
      transform_errors: fn
        _source, %{field: :paid_at} = error -> %{error | field: :paid_on}
        _source, error -> error
      end
    )
    |> to_form()
  end

  defp used_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {key, _} -> String.starts_with?(key, "_unused_") end)
    |> Map.new(fn {key, value} -> {key, used_params(value)} end)
  end

  defp used_params(value), do: value

  defp payment_params(%{"paid_at" => _} = params), do: params

  defp payment_params(params) do
    paid_at =
      with {:ok, date} <- Date.from_iso8601(params["paid_on"] || ""),
           {:ok, datetime} <- DateTime.new(date, ~T[12:00:00], ShopTime.timezone()) do
        datetime
      else
        _ -> params["paid_on"]
      end

    Map.merge(params, %{"amount" => normalize_decimal(params["amount"]), "paid_at" => paid_at})
  end

  defp normalize_decimal(value) when is_binary(value), do: value |> String.trim() |> String.replace(",", ".")
  defp normalize_decimal(%Decimal{} = value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)
  defp normalize_decimal(value), do: value

  # Shown as Jennie types it, the Finnish way, once the form has read it as a number.
  defp decimal_comma(%Decimal{} = value), do: value |> Decimal.to_string(:normal) |> String.replace(".", ",")
  defp decimal_comma(value), do: value

  defp empty_line(tax_rates) do
    rate =
      case tax_rates do
        [rate | _] -> rate.percentage |> Decimal.mult(100) |> Decimal.normalize() |> Decimal.to_string(:normal)
        [] -> "25.5"
      end

    %{"description" => "", "quantity" => "1", "unit_price" => "", "vat_rate" => rate}
    |> Map.merge(Map.new(~w(description quantity unit_price vat_rate), &{"_unused_" <> &1, ""}))
  end

  defp form_value(%Date{} = date), do: Date.to_iso8601(date)
  defp form_value(nil), do: ""
  defp form_value(value), do: value
end

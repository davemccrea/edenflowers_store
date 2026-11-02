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
  alias EdenflowersWeb.Admin.InvoicesLive
  alias EdenflowersWeb.Layouts

  @fields ~w(buyer_name buyer_email buyer_address business_customer company_name business_id billing_address customer_reference invoice_date due_date locale supply_date supply_description)
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
    payments: [:undoable?],
    credit_note: [:invoice]
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
    params = %{
      "invoice_date" => Date.to_iso8601(ShopTime.today()),
      "due_date" => Date.to_iso8601(Invoice.default_due_date()),
      "locale" => Locales.default(),
      "business_customer" => "false",
      "lines" => %{"0" => empty_line(socket.assigns.tax_rates)}
    }

    {:noreply, socket |> assign(invoice: nil, page_title: ~t"New invoice", editable: true) |> assign_form(params)}
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
          class="space-y-6"
        >
          <div class="admin-card divide-base-content/12 divide-y">
            <.form_section title={~t"Customer"} joined>
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
                <.input
                  field={@form[:buyer_address]}
                  type="textarea"
                  label={~t"Postal address"}
                  class="textarea w-full"
                  rows="3"
                />
                <.input field={@form[:customer_reference]} label={~t"Customer reference (optional)"} class="input w-full" />
              </div>
              <.input field={@form[:business_customer]} type="checkbox" label={~t"Business customer"} />
              <div :if={@form[:business_customer].value in [true, "true"]} class="mt-4 grid gap-4 sm:grid-cols-2">
                <.input field={@form[:company_name]} label={~t"Company name"} class="input w-full" />
                <.input field={@form[:business_id]} label={~t"Y-tunnus"} class="input w-full" />
                <.input
                  field={@form[:billing_address]}
                  type="textarea"
                  label={~t"Billing address"}
                  class="textarea w-full"
                  rows="3"
                />
              </div>
            </.form_section>
            <.form_section title={~t"Dates and language"} joined>
              <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                <.input field={@form[:invoice_date]} type="date" label={~t"Invoice date"} class="input w-full" required />
                <.input field={@form[:due_date]} type="date" label={~t"Due date"} class="input w-full" required />
                <.input
                  field={@form[:locale]}
                  type="select"
                  label={~t"Language"}
                  options={Enum.map(Locales.all(), &{Locales.name(&1), &1})}
                  class="select w-full"
                />
                <.input
                  field={@form[:supply_date]}
                  type="date"
                  label={~t"Supply / advance date (optional)"}
                  class="input w-full"
                />
                <div class="sm:col-span-2">
                  <.input
                    field={@form[:supply_description]}
                    label={~t"Supply / advance details (optional)"}
                    class="input w-full"
                  />
                </div>
              </div>
            </.form_section>
            <.form_section title={~t"Items"} joined>
              <:description>{~t"Prices include VAT."}</:description>
              <div class="space-y-5">
                <fieldset
                  :for={{line_form, index} <- Enum.with_index(@line_forms)}
                  id={"invoice-line-#{index}"}
                  class="border-base-content/12 border-b pb-5 last:border-0"
                >
                  <legend class="sr-only">{~t"Item"} {index + 1}</legend>
                  <div class="grid gap-3 sm:grid-cols-3 lg:grid-cols-[minmax(0,3fr)_1fr_1fr_1fr_auto] lg:items-end">
                    <div class="min-w-0 sm:col-span-3 lg:col-span-1">
                      <.input
                        field={line_form[:description]}
                        id={"line-#{index}-description"}
                        label={~t"Description"}
                        class="input w-full"
                      />
                    </div>
                    <.input
                      field={line_form[:quantity]}
                      id={"line-#{index}-quantity"}
                      label={~t"Qty"}
                      inputmode="decimal"
                      class="input w-full tabular-nums"
                    />
                    <.input
                      field={line_form[:unit_price]}
                      id={"line-#{index}-price"}
                      label={~t"Price each (€)"}
                      inputmode="decimal"
                      class="input w-full tabular-nums"
                    />
                    <.input
                      field={line_form[:vat_rate]}
                      id={"line-#{index}-vat"}
                      type="select"
                      label={~t"VAT"}
                      value={normalize_decimal(line_form[:vat_rate].value)}
                      options={vat_options(@tax_rates, line_form[:vat_rate].value, @locale)}
                      class="select w-full"
                    />
                    <.button
                      type="button"
                      phx-click="remove_line"
                      phx-value-index={index}
                      variant="ghost"
                      size="sm"
                      class="btn-square justify-self-end sm:col-span-3 lg:col-span-1"
                      aria-label={~t"Remove item #{number = index + 1}"}
                    ><.icon name="hero-trash" class="h-4 w-4" /></.button>
                  </div>
                </fieldset>
              </div>
              <.button type="button" phx-click="add_line" variant="secondary" size="sm"><.icon
                name="hero-plus"
                class="h-4 w-4"
              /> {~t"Add item"}</.button>
            </.form_section>
          </div>
          <.totals snapshot={@totals_preview} locale={@locale} draft show_errors={@submitted} />
        </.form>
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
              <dl class="mt-5 grid grid-cols-2 gap-4 sm:grid-cols-4">
                <div>
                  <dt class="text-base-content/75 text-sm">{~t"Invoice date"}</dt><dd class="tabular-nums">
                    {Format.date(@invoice.invoice_date, @locale)}
                  </dd>
                </div>
                <div>
                  <dt class="text-base-content/75 text-sm">{~t"Due date"}</dt><dd class="tabular-nums">
                    {Format.date(@invoice.due_date, @locale)}
                  </dd>
                </div>
                <div>
                  <dt class="text-base-content/75 text-sm">{~t"Paid"}</dt><dd class="tabular-nums">
                    {Format.currency(@invoice.amount_paid, @locale)}
                  </dd>
                </div>
                <div :if={@invoice.status != :cancelled}>
                  <dt class="text-base-content/75 text-sm">{~t"Balance"}</dt><dd class="tabular-nums">
                    {Format.currency(@invoice.amount_unpaid, @locale)}
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
            <.totals snapshot={{:ok, @invoice.financial_snapshot}} locale={@locale} />
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
                class="mt-5 space-y-4"
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
            </.widget>
            <.widget title={~t"Corrections"}>
              <.form
                :if={@invoice.cancellable?}
                for={@credit_form}
                id="invoice-credit-form"
                phx-change="validate_credit"
                phx-submit="credit"
                class="space-y-4"
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
              <p :if={@invoice.status in [:open, :paid] && !@invoice.cancellable?} id="accountant-correction">
                {~t"For corrections to a paid or partly paid invoice, contact the accountant."}
              </p>
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
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :snapshot, :any, required: true
  attr :locale, :string, required: true
  attr :draft, :boolean, default: false
  attr :show_errors, :boolean, default: true

  defp totals(assigns) do
    ~H"""
    <.widget id="invoice-totals" title={if @draft, do: ~t"Draft totals", else: ~t"Invoice totals"}>
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
            <.money_row label={~t"Total incl. VAT"} amount={Decimal.new(snapshot["gross"])} locale={@locale} strong />
          </dl>
        <% {:error, message} -> %>
          <p :if={@show_errors} role="status" class="text-base-content/75">{message}</p>
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
    {:noreply, socket |> assign(error: nil) |> assign_form(params, true)}
  end

  def handle_event("recover", %{"invoice" => params}, socket),
    do: {:noreply, socket |> assign(error: nil) |> assign_form(params, true)}

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

  def handle_event("add_line", _params, socket),
    do: {:noreply, change_lines(socket, socket.assigns.lines ++ [empty_line(socket.assigns.tax_rates)])}

  def handle_event("remove_line", %{"index" => index}, socket),
    do: {:noreply, change_lines(socket, List.delete_at(socket.assigns.lines, String.to_integer(index)))}

  def handle_event("save", %{"invoice" => params} = input, socket) do
    params = used_params(params)
    socket = assign(socket, submitted: true, issue_attempted: input["intent"] == "issue")
    result = AshPhoenix.Form.submit(socket.assigns.form, params: params)

    socket =
      case result do
        {:ok, draft} -> assign(socket, :invoice, draft)
        _ -> socket
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

      {:error, _error} ->
        {:noreply,
         socket
         |> assign_form(params, true)
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
    params =
      Map.new(@fields, fn field -> {field, form_value(Map.get(invoice, String.to_existing_atom(field)))} end)
      |> Map.put("lines", indexed(invoice.lines))

    socket
    |> assign(
      invoice: invoice,
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
    |> assign_form(params)
  end

  defp assign_form(socket, params, errors? \\ false) do
    opts = [
      as: "invoice",
      actor: socket.assigns.current_user,
      params: params,
      errors: errors?,
      transform_params: fn params, _type ->
        Map.put(params, "lines", line_values(params))
      end
    ]

    form =
      if socket.assigns.invoice,
        do: AshPhoenix.Form.for_update(socket.assigns.invoice, :update_draft, opts),
        else: AshPhoenix.Form.for_create(Invoice, :create, opts)

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

    lines = line_values(params)

    line_forms =
      params
      |> Map.get("lines", %{})
      |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end)
      |> Enum.map(fn {index, line} ->
        errors = if errors?, do: InvoiceFinancials.line_errors(normalize_line(line)), else: []
        to_form(line, as: "invoice[lines][#{index}]", errors: errors)
      end)

    assign(socket,
      form: to_form(form),
      invoice_params: params,
      lines:
        params
        |> Map.get("lines", %{})
        |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end)
        |> Enum.map(&elem(&1, 1)),
      line_forms: line_forms,
      totals_preview: InvoiceFinancials.build(lines)
    )
  end

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

  defp change_lines(socket, lines),
    do: assign_form(socket, Map.put(socket.assigns.invoice_params, "lines", indexed(lines)), true)

  defp used_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {key, _} -> String.starts_with?(key, "_unused_") end)
    |> Map.new(fn {key, value} -> {key, used_params(value)} end)
  end

  defp used_params(value), do: value

  defp indexed(lines), do: lines |> Enum.with_index() |> Map.new(fn {line, index} -> {to_string(index), line} end)

  defp line_values(%{"lines" => lines}) when is_list(lines), do: Enum.map(lines, &normalize_line/1)

  defp line_values(params) do
    params
    |> Map.get("lines", %{})
    |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end)
    |> Enum.map(fn {_index, line} -> normalize_line(line) end)
  end

  defp normalize_line(line) do
    line
    |> Map.take(~w(description quantity unit_price vat_rate))
    |> Map.new(fn {key, value} ->
      {key, if(key in ~w(quantity unit_price vat_rate), do: normalize_decimal(value), else: value)}
    end)
  end

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
  defp normalize_decimal(value), do: value

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

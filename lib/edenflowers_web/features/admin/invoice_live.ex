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
  alias EdenflowersWeb.Admin.Drawers
  alias EdenflowersWeb.Admin.EmailDrawer
  alias EdenflowersWeb.Admin.InvoiceLog
  alias EdenflowersWeb.Admin.InvoicesLive
  alias EdenflowersWeb.Admin.OrderLog
  alias EdenflowersWeb.Layouts

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
    :order,
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
       customer_term: "",
       customers: %{},
       email_form: nil,
       email_kind: nil,
       preview: nil,
       log: [],
       tax_rates: Pricing.list_selectable_tax_rates!(actor: socket.assigns.current_user)
     )}
  end

  # Already showing it: a draft saved on the way to a failed issue moved here without reloading.
  def handle_params(%{"id" => id}, _uri, %{assigns: %{invoice: %{id: id}}} = socket), do: {:noreply, socket}

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
          "payment_term_days" => to_string(Invoice.default_payment_term_days()),
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
        <.admin_page_header title={@page_title} back={back(@invoice)} sticky={@editable}>
          <:subtitle :if={!@editable}>
            <span class="block">
              {@invoice.buyer} · <span class="tabular-nums">{Format.currency(@invoice.amount, @locale)}</span>
            </span>
            <span class="mt-2 flex flex-wrap items-center gap-1.5">
              <.badge tone={InvoicesLive.status_tone(@invoice.status, @invoice.overdue?)}>
                {InvoicesLive.status_label(@invoice.status, @invoice.overdue?)}
              </.badge>
              <.badge :if={@invoice.sendable? && is_nil(@invoice.sent_at)} tone={:neutral}>{~t"Not sent"}</.badge>
              <.badge
                :if={@invoice.status == :open}
                href="#invoice-payment"
                tone={:warning}
                class="tabular-nums xl:hidden"
              >
                {~t"To collect #{amount = Format.currency(@invoice.amount_unpaid, @locale)}"}
                <.icon name="hero-arrow-down" class="h-3 w-3" />
              </.badge>
            </span>
          </:subtitle>
          <:actions>
            <.button
              :if={@editable && @invoice}
              type="button"
              phx-click="destroy_draft"
              variant="secondary"
              size="sm"
              class="max-sm:btn-square"
              aria-label={~t"Delete draft"}
              data-confirm={~t"Delete this draft? This cannot be undone."}
            >
              <.icon name="hero-trash" class="h-4 w-4 sm:hidden" />
              <span class="max-sm:sr-only">{~t"Delete draft"}</span>
            </.button>
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
              :if={!@editable && @invoice.sendable?}
              type="button"
              phx-click="open_email"
              phx-value-kind="invoice"
              variant={if @invoice.sent_at && !@invoice.overdue?, do: "secondary", else: "primary"}
              size="sm"
            >
              <.icon name="hero-envelope" class="h-4 w-4" />
              {send_label(@invoice)}
            </.button>
            <.button
              :if={!@editable}
              href={~p"/admin/invoices/#{@invoice.id}/pdf"}
              target="_blank"
              rel="noopener"
              variant="secondary"
              size="sm"
            >
              <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> {~t"Download PDF"}
            </.button>
          </:actions>
        </.admin_page_header>
        <p :if={@error} id="invoice-error" role="alert" class="text-error mb-5 whitespace-pre-line">{@error}</p>
        <.email_drawer
          :if={!@editable}
          form={@email_form}
          preview={@preview}
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
        >
          <%!-- The same sheet the issued invoice shows, with fields where its values will be. --%>
          <article id="invoice-sheet" class="admin-card min-w-0 p-4 sm:p-8">
            <div class="grid grid-cols-1 gap-x-12 gap-y-8 xl:grid-cols-[minmax(0,1fr)_20rem]">
              <section id="invoice-customer" class="min-w-0" aria-labelledby="invoice-bill-to">
                <h2 id="invoice-bill-to" class="text-base-content mb-4 text-base font-semibold">{~t"Bill to"}</h2>
                <.customer_picker
                  field={@form[:customer]}
                  empty?={@customer_search_empty?}
                  focus="customer_focus"
                  help={~t"Search by name, company or email."}
                />
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
              </section>

              <section id="invoice-details" class="min-w-0" aria-labelledby="invoice-details-heading">
                <h2 id="invoice-details-heading" class="text-base-content mb-4 text-base font-semibold">
                  {~t"Invoice details"}
                </h2>
                <div class="space-y-4">
                  <.input
                    field={@form[:payment_term_days]}
                    type="number"
                    min="0"
                    max="365"
                    label={~t"Payment term (days)"}
                    class="input w-full"
                    required
                    help={issue_dates_hint(@form[:payment_term_days].value, @locale)}
                  />
                  <.input
                    field={@form[:supply_date]}
                    type="date"
                    label={~t"Date of supply or advance payment"}
                    class="input w-full"
                    help={~t"Needed to issue the invoice."}
                  />
                  <.input
                    field={@form[:locale]}
                    type="select"
                    label={~t"Language"}
                    options={Enum.map(Locales.all(), &{Locales.name(&1), &1})}
                    class="select w-full"
                  />
                </div>
                <details
                  id="invoice-additional-details"
                  class="group mt-5"
                  open={additional_details?(@form)}
                  phx-mounted={JS.ignore_attributes(["open"])}
                >
                  <summary class="text-base-content flex cursor-pointer list-none items-center gap-1 text-sm font-semibold">
                    {~t"Additional details (optional)"}
                    <.icon
                      name="hero-chevron-right"
                      class="text-base-content/50 h-3.5 w-3.5 transition-transform group-open:rotate-90"
                    />
                  </summary>
                  <div class="mt-4 space-y-4">
                    <.input
                      field={@form[:customer_reference]}
                      label={~t"Customer reference (optional)"}
                      class="input w-full"
                    />
                    <.input
                      field={@form[:supply_description]}
                      label={~t"Label for the date of supply (optional)"}
                      placeholder={~t"Wedding date"}
                      class="input w-full"
                    />
                  </div>
                </details>
              </section>
            </div>

            <section id="invoice-lines" class="mt-10" aria-labelledby="invoice-lines-heading">
              <h2 id="invoice-lines-heading" class="text-base-content text-base font-semibold xl:sr-only">{~t"Items"}</h2>
              <div
                aria-hidden="true"
                class={["text-base-content/75 border-base-content/12 hidden gap-3 border-b pb-2 text-xs font-semibold xl:grid", line_columns()]}
              >
                <span>{~t"Description"}</span>
                <span>{~t"Qty"}</span>
                <span>{~t"Price each (€)"}</span>
                <span>{~t"VAT"}</span>
                <span class="text-right">{~t"Total"}</span>
              </div>
              <div class="divide-base-content/12 divide-y">
                <.inputs_for :let={line_form} field={@form[:lines]}>
                  <fieldset
                    id={"invoice-line-#{line_form.index}"}
                    class={["relative grid grid-cols-2 items-start gap-3 py-4 xl:[&_label>span:first-child]:sr-only", line_columns()]}
                  >
                    <legend class="sr-only">{~t"Item"} {line_form.index + 1}</legend>
                    <div class="col-span-2 min-w-0 xl:col-span-1">
                      <.input
                        field={line_form[:description]}
                        id={"line-#{line_form.index}-description"}
                        label={~t"Description"}
                        class="input w-full"
                      />
                    </div>
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
                    <.input
                      field={line_form[:vat_rate]}
                      id={"line-#{line_form.index}-vat"}
                      type="select"
                      label={~t"VAT"}
                      value={normalize_decimal(line_form[:vat_rate].value)}
                      options={vat_options(@tax_rates, line_form[:vat_rate].value)}
                      class="select w-full"
                    />
                    <p class="text-base-content self-end pb-2.5 text-right tabular-nums xl:self-start xl:pt-2.5 xl:pb-0">
                      <span class="sr-only">{~t"Total"}</span>
                      {line_total(line_form, @locale)}
                    </p>
                    <.button
                      :if={length(@form.source.forms[:lines]) > 1}
                      type="button"
                      phx-click="remove_line"
                      phx-value-path={line_form.name}
                      variant="ghost"
                      size="sm"
                      class="btn-square absolute top-2.5 right-0 xl:static xl:mt-1"
                      aria-label={~t"Remove item #{number = line_form.index + 1}"}
                    >
                      <.icon name="hero-trash" class="h-4 w-4" />
                    </.button>
                  </fieldset>
                </.inputs_for>
              </div>
              <div class="border-base-content/12 flex flex-col gap-6 border-t pt-4 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <.button type="button" phx-click="add_line" variant="secondary" size="sm">
                    <.icon name="hero-plus" class="h-4 w-4" /> {~t"Add item"}
                  </.button>
                  <p class="text-base-content/75 mt-2 text-sm">{~t"Prices include VAT."}</p>
                </div>
                <div id="invoice-totals" class="w-full sm:max-w-xs">
                  <%= case @totals_preview do %>
                    <% {:ok, snapshot} -> %>
                      <.sheet_totals snapshot={snapshot} locale={@locale} />
                    <% {:error, message} -> %>
                      <p role="status" class="text-base-content/75 text-sm sm:text-right">
                        {if @submitted, do: message, else: ~t"Complete the items to see the total."}
                      </p>
                  <% end %>
                </div>
              </div>
            </section>
          </article>
        </.form>
        <div :if={@editable && @invoice && @log != []} class="mt-6">
          <.invoice_history log={@log} locale={@locale} />
        </div>
        <div :if={!@editable} class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <%!-- The invoice as the customer receives it, laid out like the PDF. --%>
          <article id="invoice-sheet" class="admin-card min-w-0 p-4 sm:p-8">
            <div class="grid grid-cols-1 gap-x-10 gap-y-6 sm:grid-cols-[minmax(0,1fr)_auto]">
              <section id="invoice-customer" class="min-w-0 text-sm">
                <h2 class="text-base-content/75 mb-1.5">{~t"Bill to"}</h2>
                <p class="text-base-content text-base font-semibold">{@invoice.buyer}</p>
                <p
                  :if={@invoice.business_customer}
                  class="text-base-content/90 mt-1 whitespace-pre-line break-words"
                  phx-no-format
                >{@invoice.billing_address}</p>
                <p :if={@invoice.business_customer && @invoice.business_id} class="text-base-content/90 mt-1">
                  {~t"Y-tunnus"} {@invoice.business_id}
                </p>
                <div :if={@invoice.buyer_email} class="mt-2"><.email_link email={@invoice.buyer_email} /></div>
              </section>
              <dl
                id="invoice-details"
                class="grid-cols-[auto_auto] grid content-start gap-x-6 gap-y-1.5 text-sm sm:justify-end"
              >
                <.sheet_fact label={~t"Invoice number"}>{@invoice.number}</.sheet_fact>
                <.sheet_fact label={~t"Invoice date"}>{Format.date(@invoice.invoice_date, @locale)}</.sheet_fact>
                <.sheet_fact label={~t"Due date"} class={@invoice.overdue? && "text-error font-semibold"}>
                  {Format.date(@invoice.due_date, @locale)}
                </.sheet_fact>
                <.sheet_fact label={~t"Reference number"}>
                  {Edenflowers.Payments.ReferenceNumber.format(@invoice.reference_number)}
                </.sheet_fact>
                <.sheet_fact :if={@invoice.supply_date} label={@invoice.supply_description || ~t"Date of supply"}>
                  {Format.date(@invoice.supply_date, @locale)}
                </.sheet_fact>
                <.sheet_fact :if={@invoice.customer_reference} label={~t"Customer reference"}>
                  {@invoice.customer_reference}
                </.sheet_fact>
              </dl>
            </div>

            <table id="invoice-lines" class="mt-8 w-full text-sm">
              <thead class="text-base-content/75 border-base-content/12 border-b text-left text-xs">
                <tr>
                  <th scope="col" class="pb-2 font-semibold">{~t"Description"}</th>
                  <th scope="col" class="pb-2 pl-4 text-right font-semibold max-sm:hidden">{~t"Qty"}</th>
                  <th scope="col" class="pb-2 pl-4 text-right font-semibold max-sm:hidden">{~t"Price each"}</th>
                  <th scope="col" class="pb-2 pl-4 text-right font-semibold max-sm:hidden">{~t"VAT"}</th>
                  <th scope="col" class="pb-2 pl-4 text-right font-semibold">{~t"Total"}</th>
                </tr>
              </thead>
              <tbody class="divide-base-content/12 divide-y">
                <tr :for={line <- @invoice.financial_snapshot["lines"]} class="align-top">
                  <td class="text-base-content break-words py-3">
                    {line["description"]}
                    <span class="text-base-content/75 mt-0.5 block tabular-nums sm:hidden">
                      {line["quantity"]} × {Format.currency(Decimal.new(line["unit_price"]), @locale)} · {~t"VAT"} {line[
                        "vat_rate"
                      ]}%
                    </span>
                  </td>
                  <td class="py-3 pl-4 text-right tabular-nums max-sm:hidden">{line["quantity"]}</td>
                  <td class="whitespace-nowrap py-3 pl-4 text-right tabular-nums max-sm:hidden">
                    {Format.currency(Decimal.new(line["unit_price"]), @locale)}
                  </td>
                  <td class="whitespace-nowrap py-3 pl-4 text-right tabular-nums max-sm:hidden">{line["vat_rate"]}%</td>
                  <td class="whitespace-nowrap py-3 pl-4 text-right tabular-nums">
                    {Format.currency(Decimal.new(line["gross"]), @locale)}
                  </td>
                </tr>
              </tbody>
            </table>

            <.sheet_totals
              snapshot={@invoice.financial_snapshot}
              locale={@locale}
              class="border-base-content/12 ml-auto border-t pt-3 sm:max-w-xs"
            />
          </article>

          <aside class="min-w-0 space-y-6">
            <.widget id="invoice-payment" title={~t"Payment"} class="scroll-mt-[calc(env(safe-area-inset-top)+6rem)]">
              <dl class="text-sm">
                <.money_row
                  :if={@invoice.payments != []}
                  label={~t"Invoice total"}
                  amount={@invoice.amount}
                  locale={@locale}
                />
                <.money_row
                  :for={payment <- Enum.sort_by(@invoice.payments, & &1.paid_at, DateTime)}
                  label={payment_label(payment, @locale)}
                  amount={Decimal.negate(payment.amount)}
                  locale={@locale}
                />
                <.money_row
                  :if={@invoice.status in [:open, :paid]}
                  strong
                  label={~t"Balance due"}
                  amount={@invoice.amount_unpaid}
                  locale={@locale}
                />
              </dl>
              <p
                :if={@invoice.status == :open}
                class={["mt-1 text-sm", if(@invoice.overdue?, do: "text-error font-semibold", else: "text-base-content/75")]}
              >
                {~t"Due #{date = Format.date(@invoice.due_date, @locale)}"}
              </p>
              <p :if={@invoice.sent_at} class="text-base-content/75 mt-1 text-sm">
                {~t"Last sent"}: {Format.datetime(@invoice.sent_at, @locale)}
              </p>
              <.form
                :if={@invoice.status == :open}
                for={@payment_form}
                id="invoice-payment-form"
                novalidate
                phx-change="validate_payment"
                phx-submit="record_payment"
                class="border-base-content/12 mt-4 border-t pt-4"
              >
                <h3 class="text-base-content mb-3 text-sm font-semibold">{~t"Record bank transfer"}</h3>
                <div class="grid grid-cols-2 gap-3">
                  <.input
                    field={@payment_form[:amount]}
                    value={@payment_form.source.raw_params["amount"]}
                    label={~t"Amount (€)"}
                    inputmode="decimal"
                    class="input w-full tabular-nums"
                    required
                  />
                  <.input
                    field={@payment_form[:paid_on]}
                    type="date"
                    label={~t"Payment date"}
                    class="input w-full"
                    required
                  />
                </div>
                <.button
                  type="submit"
                  variant={if @invoice.sent_at, do: "primary", else: "secondary"}
                  size="sm"
                  class="mt-3"
                >
                  <.icon name="hero-banknotes" class="h-4 w-4" /> {~t"Record payment"}
                </.button>
              </.form>
              <div
                :if={@invoice.status != :cancelled && Enum.any?(@invoice.payments, & &1.undoable?)}
                class="border-base-content/12 mt-4 border-t pt-3 text-sm"
              >
                <p class="text-base-content/75 mb-2">{~t"Entered a transfer by mistake?"}</p>
                <ul class="space-y-2">
                  <li
                    :for={payment <- Enum.filter(@invoice.payments, & &1.undoable?)}
                    class="flex items-center justify-between gap-3"
                  >
                    <span class="tabular-nums">
                      {payment_label(payment, @locale)} · {Format.currency(payment.amount, @locale)}
                    </span>
                    <.button
                      type="button"
                      phx-click="undo_payment"
                      phx-value-id={payment.id}
                      variant="secondary"
                      size="sm"
                      data-confirm={
                        ~t"Undo the #{amount = Format.currency(payment.amount, @locale)} payment by #{how = OrderLog.payment_method_label(payment.method)}? This records the opposite amount."
                      }
                    >{~t"Undo"}</.button>
                  </li>
                </ul>
              </div>
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
              class="admin-card group p-4 sm:p-5"
              phx-mounted={JS.ignore_attributes(["open"])}
            >
              <summary class="text-base-content flex cursor-pointer list-none items-center gap-1 text-base font-semibold">
                {~t"Correct this invoice"}
                <.icon
                  name="hero-chevron-right"
                  class="text-base-content/50 h-4 w-4 transition-transform group-open:rotate-90"
                />
              </summary>
              <.form
                for={@credit_form}
                id="invoice-credit-form"
                phx-change="validate_credit"
                phx-submit="credit"
                class="mt-4 space-y-4"
              >
                <p class="text-base-content/75 text-sm">
                  {~t"A full credit note reverses this unpaid invoice and its VAT."}
                </p>
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
              <div class="flex flex-wrap items-center gap-3">
                <p class="w-full text-sm tabular-nums">
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

  attr :snapshot, :map, required: true
  attr :locale, :string, required: true
  attr :class, :any, default: nil

  defp sheet_totals(assigns) do
    ~H"""
    <dl class={["text-sm", @class]}>
      <.money_row label={~t"Total excl. VAT"} amount={Decimal.new(@snapshot["base"])} locale={@locale} />
      <.money_row
        :for={row <- @snapshot["vat_breakdown"]}
        label={~t"VAT #{rate = row["rate"]}%"}
        amount={Decimal.new(row["vat"])}
        locale={@locale}
      />
      <.money_row strong label={~t"Total incl. VAT"} amount={Decimal.new(@snapshot["gross"])} locale={@locale} />
    </dl>
    """
  end

  def handle_event("live_select_change", %{"id" => "customer-select", "text" => term}, socket),
    do: {:noreply, show_customers(socket, String.trim(term))}

  # An empty search lists the latest customers, so a repeat invoice is a click away.
  def handle_event("customer_focus", _params, %{assigns: %{customer_term: ""}} = socket),
    do: {:noreply, show_customers(socket, "")}

  def handle_event("customer_focus", _params, socket), do: {:noreply, socket}

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

      {:error, issue_error} ->
        {:noreply,
         socket
         |> put_form(socket |> draft_form(socket.assigns.invoice) |> AshPhoenix.Form.validate(params))
         |> assign(error: issue_message(issue_error), page_title: ~t"Invoice draft")
         |> push_patch(to: ~p"/admin/invoices/#{socket.assigns.invoice.id}", replace: true)}
    end
  end

  def handle_event("send_email", %{"email" => params}, %{assigns: %{email_form: form, preview: preview}} = socket)
      when not is_nil(form) and not is_nil(preview) do
    %{invoice: invoice, email_kind: kind, current_user: actor} = socket.assigns

    result =
      case kind do
        :invoice -> Payments.send_invoice(invoice, Drawers.email_edits(params), actor: actor)
        :credit_note -> Payments.send_credit_note(invoice.credit_note, Drawers.email_edits(params), actor: actor)
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

  def handle_event("destroy_draft", _params, %{assigns: %{invoice: invoice}} = socket) do
    case Payments.destroy_invoice_draft(invoice, actor: socket.assigns.current_user) do
      :ok ->
        {_label, path} = back(invoice)
        {:noreply, socket |> put_flash(:info, ~t"Draft deleted.") |> push_navigate(to: path)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, ~t"This invoice is no longer a draft, so it can't be deleted.")}
    end
  end

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

  attr :label, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  defp sheet_fact(assigns) do
    ~H"""
    <dt class="text-base-content/75">{@label}</dt>
    <dd class={["text-base-content break-words text-right tabular-nums", @class]}>{render_slot(@inner_block)}</dd>
    """
  end

  defp send_label(%{overdue?: true}), do: ~t"Send reminder"
  defp send_label(%{sent_at: nil}), do: ~t"Send invoice"
  defp send_label(_invoice), do: ~t"Resend invoice"

  defp payment_label(%{reverses_payment_id: nil} = payment, locale),
    do: ~t"Paid #{date = Format.date(payment.paid_at, locale)}"

  defp payment_label(payment, locale), do: ~t"Undone #{date = Format.date(payment.paid_at, locale)}"

  defp back(%{order: %Edenflowers.Orders.Order{} = order}),
    do: {~t"Order #{order.order_reference}", ~p"/admin/orders/#{order.id}"}

  defp back(_invoice), do: {~t"Invoices", ~p"/admin/invoices"}

  # An invoice for an order can be refused for the order's sake, which no field shows.
  defp issue_message(error) do
    error
    |> Ash.Error.to_error_class()
    |> Map.get(:errors, [])
    |> Enum.find_value(~t"Check the fields marked below and try again.", fn
      %Ash.Error.Changes.InvalidChanges{fields: [], message: message} when is_binary(message) -> message
      _field_error -> nil
    end)
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

  defp line_total(line_form, locale) do
    case {line_form[:quantity].value, line_form[:unit_price].value} do
      {%Decimal{} = quantity, %Decimal{} = unit_price} ->
        Format.currency(InvoiceFinancials.line_gross(quantity, unit_price), locale)

      _incomplete ->
        nil
    end
  end

  defp line_columns, do: "xl:grid-cols-[minmax(0,1fr)_4.5rem_7rem_9.5rem_6.5rem_2.5rem]"

  defp additional_details?(form),
    do: Enum.any?([:customer_reference, :supply_description], &(form[&1].value not in [nil, ""]))

  # Issuing dates it today, so the due date shown is the one it gets if issued now.
  defp issue_dates_hint(term, locale) do
    case Integer.parse(to_string(term)) do
      {days, ""} when days in 0..365 ->
        due = Date.add(ShopTime.today(), days)
        ~t"Dated the day it is issued. Issued today, it is due #{date = Format.date(due, locale)}."

      _invalid ->
        ~t"Dated the day it is issued."
    end
  end

  defp email_record(nil, _invoice), do: nil
  defp email_record(:invoice, invoice), do: invoice
  defp email_record(:credit_note, nil), do: nil
  defp email_record(:credit_note, invoice), do: invoice.credit_note

  defp show_customers(socket, term) do
    customers =
      Payments.find_invoice_customers!(if(term == "", do: nil, else: term), actor: socket.assigns.current_user)

    options = Enum.map(customers, &{customer_label(&1), &1.id})
    send_update(LiveSelect.Component, id: "customer-select", options: options)

    assign(socket,
      customer_term: term,
      customers: Map.new(customers, &{&1.id, &1.details}),
      customer_search_empty?: term != "" && customers == []
    )
  end

  defp customer_label(customer),
    do: [customer.buyer, customer.buyer_email] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")

  # Fills the customer fields once, when a customer is picked; edits after that are kept.
  defp prefill_customer(%{"customer" => id} = params, assigns) when id not in [nil, ""] do
    picked = assigns.form[:customer].value

    case assigns.customers do
      %{^id => details} when id != picked -> Map.merge(params, customer_params(details))
      _ -> params
    end
  end

  defp prefill_customer(params, _assigns), do: params

  defp customer_params(details), do: Map.new(details, fn {field, value} -> {to_string(field), form_value(value)} end)

  defp vat_options(tax_rates, current) do
    options =
      Enum.map(tax_rates, fn rate ->
        {rate.name, rate.percentage |> Decimal.mult(100) |> Decimal.normalize() |> Decimal.to_string(:normal)}
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

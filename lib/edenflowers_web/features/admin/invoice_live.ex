defmodule EdenflowersWeb.Admin.InvoiceLive do
  @moduledoc "Standalone invoice drafting and issued document management."
  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}
  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Locales
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoiceFinancials
  alias Edenflowers.ShopTime
  alias EdenflowersWeb.Admin.InvoicesLive
  alias EdenflowersWeb.Layouts

  @fields ~w(buyer_name buyer_email buyer_address business_customer company_name business_id billing_address customer_reference invoice_date due_date locale supply_date supply_description)
  @load [
    :editable?,
    :status,
    :buyer,
    :overdue?,
    :amount_paid,
    :amount_unpaid,
    :sendable?,
    :cancellable?,
    :credit_note,
    payments: [:undoable?]
  ]
  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, locale: Localize.get_locale(), error: nil)}
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
      "lines" => %{"0" => empty_line()}
    }

    {:noreply, socket |> assign(invoice: nil, page_title: ~t"New invoice", editable: true) |> assign_form(params)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={@page_title} back={{~t"Invoices", ~p"/admin/invoices"}} sticky>
          <:actions>
            <.button :if={@editable} type="submit" form="invoice-form" variant="secondary" size="sm">{~t"Save draft"}</.button>
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
        <.form
          :if={@editable}
          for={@form}
          id="invoice-form"
          phx-change="validate"
          phx-submit="save"
          data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
          class="space-y-6"
        >
          <div class="admin-card divide-base-content/12 divide-y">
            <.form_section title={~t"Buyer"} joined>
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@form[:buyer_name]} label={~t"Name"} class="input w-full" autocomplete="name" />
                <.input
                  field={@form[:buyer_email]}
                  type="email"
                  label={~t"Email"}
                  class="input w-full"
                  autocomplete="email"
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
                <.input
                  field={@form[:supply_description]}
                  label={~t"Supply / advance details (optional)"}
                  class="input w-full sm:col-span-2"
                />
              </div>
            </.form_section>
            <.form_section title={~t"Billed lines"} joined>
              <div class="space-y-5">
                <fieldset
                  :for={{line, index} <- Enum.with_index(@lines)}
                  id={"invoice-line-#{index}"}
                  class="border-base-content/12 border-b pb-5 last:border-0"
                >
                  <legend class="sr-only">{~t"Billed line"} {index + 1}</legend>
                  <div class="grid gap-3 sm:grid-cols-3 lg:grid-cols-[minmax(0,3fr)_1fr_1fr_1fr_auto] lg:items-end">
                    <.input
                      name={"invoice[lines][#{index}][description]"}
                      id={"line-#{index}-description"}
                      value={line["description"]}
                      label={~t"Description"}
                      class="input w-full sm:col-span-3 lg:col-span-1"
                    />
                    <.input
                      name={"invoice[lines][#{index}][quantity]"}
                      id={"line-#{index}-quantity"}
                      value={line["quantity"]}
                      label={~t"Quantity"}
                      inputmode="decimal"
                      class="input w-full tabular-nums"
                    />
                    <.input
                      name={"invoice[lines][#{index}][unit_price]"}
                      id={"line-#{index}-price"}
                      value={line["unit_price"]}
                      label={~t"Unit price incl. VAT (€)"}
                      inputmode="decimal"
                      class="input w-full tabular-nums"
                    />
                    <.input
                      name={"invoice[lines][#{index}][vat_rate]"}
                      id={"line-#{index}-vat"}
                      value={line["vat_rate"]}
                      label={~t"VAT (%)"}
                      inputmode="decimal"
                      class="input w-full tabular-nums"
                    />
                    <.button
                      type="button"
                      phx-click="remove_line"
                      phx-value-index={index}
                      variant="ghost"
                      aria-label={~t"Remove billed line"}
                    ><.icon name="hero-trash" class="h-4 w-4" /></.button>
                  </div>
                </fieldset>
              </div>
              <.button type="button" phx-click="add_line" variant="secondary" size="sm">{~t"Add line"}</.button>
            </.form_section>
          </div>
          <.totals snapshot={@preview} locale={@locale} draft />
        </.form>
        <div :if={!@editable} class="space-y-6">
          <section class="admin-card p-4 sm:p-5">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div>
                <h2 class="text-balance text-lg font-semibold">{@invoice.buyer}</h2>
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
              <.badge tone={InvoicesLive.status_tone(@invoice.status, @invoice.overdue?)}>
                {InvoicesLive.status_label(@invoice.status, @invoice.overdue?)}
              </.badge>
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
          </section>
          <section class="admin-card p-4 sm:p-5">
            <h2 class="text-balance mb-4 text-lg font-semibold">{~t"Billed lines"}</h2>
            <dl class="divide-base-content/12 divide-y">
              <div :for={line <- @invoice.financial_snapshot["lines"]} class="flex justify-between gap-4 py-3">
                <div>
                  <dt>{line["description"]}</dt><dd class="text-base-content/75 text-sm tabular-nums">
                    {line["quantity"]} × {Format.currency(Decimal.new(line["unit_price"]), @locale)} · {~t"VAT"} {line[
                      "vat_rate"
                    ]}%
                  </dd>
                </div>
                <dd class="tabular-nums">{Format.currency(Decimal.new(line["gross"]), @locale)}</dd>
              </div>
            </dl>
          </section>
          <.totals snapshot={{:ok, @invoice.financial_snapshot}} locale={@locale} />
          <section :if={@invoice.sendable?} class="admin-card p-4 sm:p-5">
            <h2 class="text-balance mb-4 text-lg font-semibold">{~t"Email invoice"}</h2>
            <p class="text-base-content/75 mb-4 text-sm">{@invoice.buyer_email}</p>
            <p :if={@invoice.sent_at} class="mb-4 text-sm">{~t"Last sent"}: {Format.date(@invoice.sent_at, @locale)}</p>
            <.form for={@email_form} id="invoice-email-form" phx-submit="send_invoice" class="space-y-4">
              <.input
                field={@email_form[:message]}
                type="textarea"
                label={~t"Message (optional)"}
                class="textarea w-full"
                rows="2"
              />
              <.button type="submit" variant="primary">{if @invoice.overdue?,
                do: ~t"Send reminder",
                else: if(@invoice.sent_at, do: ~t"Resend invoice", else: ~t"Send invoice")}</.button>
            </.form>
          </section>
          <section class="admin-card p-4 sm:p-5">
            <h2 class="text-balance mb-4 text-lg font-semibold">{~t"Bank transfers"}</h2>
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
              phx-submit="record_payment"
              class="mt-5 grid gap-4 sm:grid-cols-[1fr_1fr_auto] sm:items-end"
            >
              <.input
                field={@payment_form[:amount]}
                label={~t"Amount (€)"}
                inputmode="decimal"
                class="input w-full tabular-nums"
                required
              />
              <.input field={@payment_form[:paid_on]} type="date" label={~t"Payment date"} class="input w-full" required />
              <.button type="submit" variant="primary">{~t"Record bank transfer"}</.button>
            </.form>
          </section>
          <section class="admin-card p-4 sm:p-5">
            <h2 class="text-balance mb-4 text-lg font-semibold">{~t"Corrections"}</h2>
            <.form
              :if={@invoice.cancellable?}
              for={@credit_form}
              id="invoice-credit-form"
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
            <div :if={@invoice.credit_note} class="space-y-4">
              <p>
                {~t"Credit note"} {@invoice.credit_note.number} · {Format.date(@invoice.credit_note.credit_date, @locale)}
              </p>
              <.button
                href={~p"/admin/credit-notes/#{@invoice.credit_note.id}"}
                target="_blank"
                rel="noopener"
                variant="secondary"
              >{~t"Download credit note"}</.button>
              <.button type="button" phx-click="send_credit" variant="primary">{~t"Send credit note"}</.button>
            </div>
          </section>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :snapshot, :any, required: true
  attr :locale, :string, required: true
  attr :draft, :boolean, default: false

  defp totals(assigns) do
    ~H"""
    <section id="invoice-totals" class="admin-card p-4 sm:p-5">
      <h2 class="text-balance mb-4 text-lg font-semibold">{if @draft, do: ~t"Draft totals", else: ~t"Invoice totals"}</h2>
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
            <div class="border-base-content/12 flex justify-between border-t pt-3 text-lg font-semibold">
              <dt>{~t"Total incl. VAT"}</dt><dd>{Format.currency(Decimal.new(snapshot["gross"]), @locale)}</dd>
            </div>
          </dl>
        <% {:error, message} -> %>
          <p role="status" class="text-base-content/75">{message}</p>
      <% end %>
    </section>
    """
  end

  def handle_event("validate", %{"invoice" => params}, socket), do: {:noreply, assign_form(socket, params)}

  def handle_event("add_line", _params, socket),
    do: {:noreply, change_lines(socket, socket.assigns.lines ++ [empty_line()])}

  def handle_event("remove_line", %{"index" => index}, socket),
    do: {:noreply, change_lines(socket, List.delete_at(socket.assigns.lines, String.to_integer(index)))}

  def handle_event("save", %{"invoice" => params} = input, socket) do
    attrs = params |> Map.take(@fields) |> Map.put("lines", line_values(params))

    result =
      if socket.assigns.invoice,
        do: Payments.update_invoice_draft(socket.assigns.invoice, attrs, actor: socket.assigns.current_user),
        else: Payments.create_invoice(attrs, actor: socket.assigns.current_user)

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

      {:error, error} ->
        {:noreply, socket |> assign_form(params) |> assign(error: Exception.message(error))}
    end
  end

  def handle_event("send_invoice", %{"email" => params}, socket) do
    case Payments.send_invoice(socket.assigns.invoice, params, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> refresh() |> put_flash(:info, ~t"Invoice emailed.")}

      {:error, _} ->
        {:noreply,
         socket
         |> refresh()
         |> put_flash(:error, ~t"Could not email the invoice. It remains issued; try sending again.")}
    end
  end

  def handle_event("record_payment", %{"payment" => params}, socket) do
    result =
      with {:ok, date} <- Date.from_iso8601(params["paid_on"]),
           {:ok, datetime} <- DateTime.new(date, ~T[12:00:00], ShopTime.timezone()) do
        Payments.record_invoice_payment(socket.assigns.invoice, params["amount"], %{paid_at: datetime},
          actor: socket.assigns.current_user
        )
      end

    finish(socket, result, ~t"Bank transfer recorded.")
  end

  def handle_event("undo_payment", %{"id" => id}, socket),
    do:
      finish(
        socket,
        Payments.undo_invoice_payment(socket.assigns.invoice, id, actor: socket.assigns.current_user),
        ~t"Payment reversed."
      )

  def handle_event("credit", %{"credit" => params}, socket),
    do:
      finish(
        socket,
        Payments.cancel_invoice(Map.put(params, "invoice_id", socket.assigns.invoice.id),
          actor: socket.assigns.current_user
        ),
        ~t"Credit note issued."
      )

  def handle_event("send_credit", _params, socket) do
    case Payments.send_credit_note(socket.assigns.invoice.credit_note, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> refresh() |> put_flash(:info, ~t"Credit note emailed.")}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, ~t"Could not email the credit note. Try again in a moment.")}
    end
  end

  defp finish(socket, {:ok, _}, message), do: {:noreply, socket |> refresh() |> put_flash(:info, message)}

  defp finish(socket, {:error, error}, _),
    do:
      {:noreply,
       assign(socket,
         error: if(is_exception(error), do: Exception.message(error), else: ~t"Check the entered values and try again.")
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
      email_form: to_form(%{"message" => ""}, as: :email),
      credit_form: to_form(%{"reason" => ""}, as: :credit),
      payment_form:
        to_form(
          %{
            "amount" => Decimal.to_string(invoice.amount_unpaid, :normal),
            "paid_on" => Date.to_iso8601(ShopTime.today())
          },
          as: :payment
        )
    )
    |> assign_form(params)
  end

  defp assign_form(socket, params) do
    lines = line_values(params)
    assign(socket, form: to_form(params, as: :invoice), lines: lines, preview: InvoiceFinancials.build(lines))
  end

  defp change_lines(socket, lines),
    do: assign_form(socket, Map.put(socket.assigns.form.params, "lines", indexed(lines)))

  defp indexed(lines), do: lines |> Enum.with_index() |> Map.new(fn {line, index} -> {to_string(index), line} end)

  defp line_values(params),
    do:
      params
      |> Map.get("lines", %{})
      |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end)
      |> Enum.map(fn {_index, line} ->
        Map.new(line, fn {key, value} ->
          {key,
           if(key in ["quantity", "unit_price", "vat_rate"] and is_binary(value),
             do: value |> String.trim() |> String.replace(",", "."),
             else: value
           )}
        end)
      end)

  defp empty_line, do: %{"description" => "", "quantity" => "1", "unit_price" => "", "vat_rate" => "25.5"}
  defp form_value(%Date{} = date), do: Date.to_iso8601(date)
  defp form_value(nil), do: ""
  defp form_value(value), do: value
end

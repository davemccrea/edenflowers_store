defmodule EdenflowersWeb.Admin.InvoiceDrawer do
  @moduledoc """
  Invoicing an order or a Course booking from the page Jennie is already on.
  The drawer creates an invoice, emailing it at once unless she unticks it,
  lets her fill in the business details it still needs, and sends one made
  earlier. It also cancels an open invoice with nothing paid on it by
  issuing a Credit note, emailed at once unless she unticks it.
  `invoice_list/1` lists a purchase's invoices and credit notes with their
  PDFs.

  Render it once per page with `id`, `purchases` (the orders or bookings the
  page shows, each loaded with `purchase_load/0`), `locale` and
  `current_user`. Open it with `open_create/2`, `open_send/2` or
  `open_cancel/2`. After any
  change it sends the page `{InvoiceDrawer, {flash_kind, message}}`, so the
  page reloads what it shows and flashes the message.
  """

  use EdenflowersWeb, {:live_component, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.Drawers

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email.Preview
  alias Edenflowers.Format
  alias Edenflowers.Locales
  alias Edenflowers.Payments
  alias Edenflowers.Payments.CreditNote
  alias Edenflowers.Payments.Invoice

  @doc "What every purchase passed in needs loaded."
  def purchase_load do
    [
      :invoiceable?,
      :uninvoiced_balance,
      :buyer_details_complete?,
      :business_details_complete?,
      :missing_business_details,
      invoices: [:status, :cancellable?, :credit_note]
    ]
  end

  @doc "Opens drawer `id` to create an invoice for `purchase`."
  def open_create(id, purchase), do: JS.push("open_create", target: "##{id}", value: %{purchase_id: purchase.id})

  @doc "Opens drawer `id` to email `invoice` to the customer."
  def open_send(id, %Invoice{} = invoice), do: JS.push("open_send", target: "##{id}", value: %{invoice_id: invoice.id})

  def open_send(id, %CreditNote{} = credit_note),
    do: JS.push("open_send_credit_note", target: "##{id}", value: %{credit_note_id: credit_note.id})

  @doc "Opens drawer `id` to cancel `invoice` with a Credit note."
  def open_cancel(id, invoice), do: JS.push("open_cancel", target: "##{id}", value: %{invoice_id: invoice.id})

  attr :invoices, :list, required: true, doc: "with `status`, `cancellable?` and `credit_note` loaded"
  attr :locale, :string, required: true
  attr :drawer, :string, required: true, doc: "the InvoiceDrawer's id, which Send opens"

  @doc """
  A purchase's invoices, oldest first, each with its PDF and, until it has
  gone, Send. One with nothing paid on it can be cancelled; a cancelled one
  shows the credit note that cancels it, with its own PDF and Send.
  """
  def invoice_list(assigns) do
    ~H"""
    <ul class="divide-base-content/12 divide-y text-sm">
      <li :for={invoice <- @invoices} id={"invoice-#{invoice.id}"} class="space-y-0.5 py-2 first:pt-0 last:pb-0">
        <p class="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span class="font-semibold tabular-nums">{~t"Invoice #{number = invoice.number}"}</span>
          <span class="tabular-nums">{Format.currency(invoice.amount, @locale)}</span>
          <.badge tone={status_tone(invoice.status)}>{status_label(invoice.status)}</.badge>
        </p>
        <p class="text-base-content/75 tabular-nums">
          {~t"Dated #{date = Format.date(invoice.invoice_date, @locale)}, due #{due = Format.date(invoice.due_date, @locale)}"}
        </p>
        <p class="flex flex-wrap items-center gap-x-3 gap-y-1">
          <span :if={invoice.sent_at} class="text-base-content/75">
            {~t"Sent #{date = Format.date(invoice.sent_at, @locale)}"}
          </span>
          <span :if={!invoice.sent_at} class="text-warning-content font-semibold">{~t"Not sent"}</span>
          <.link
            href={~p"/admin/invoices/#{invoice.id}"}
            target="_blank"
            rel="noopener"
            class="link link-primary touch-target inline-flex items-center gap-1"
          >
            {~t"PDF"} <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
          </.link>
          <button
            :if={!invoice.sent_at}
            type="button"
            phx-click={open_send(@drawer, invoice)}
            class="link link-primary touch-target"
          >
            {~t"Send"}
          </button>
          <button
            :if={invoice.cancellable?}
            type="button"
            phx-click={open_cancel(@drawer, invoice)}
            class="link link-error touch-target"
          >
            {~t"Cancel"}
          </button>
        </p>
        <.credit_note_line :if={invoice.credit_note} credit_note={invoice.credit_note} locale={@locale} drawer={@drawer} />
      </li>
    </ul>
    """
  end

  attr :credit_note, CreditNote, required: true
  attr :locale, :string, required: true
  attr :drawer, :string, required: true

  defp credit_note_line(assigns) do
    ~H"""
    <p id={"credit-note-#{@credit_note.id}"} class="flex flex-wrap items-center gap-x-3 gap-y-1">
      <span class="tabular-nums">
        {~t"Credit note #{number = @credit_note.number}, #{date = Format.date(@credit_note.credit_date, @locale)}"}
      </span>
      <span :if={!@credit_note.sent_at} class="text-warning-content font-semibold">{~t"Not sent"}</span>
      <.link
        href={~p"/admin/credit-notes/#{@credit_note.id}"}
        target="_blank"
        rel="noopener"
        class="link link-primary touch-target inline-flex items-center gap-1"
      >
        {~t"PDF"} <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
      </.link>
      <button
        :if={!@credit_note.sent_at}
        type="button"
        phx-click={open_send(@drawer, @credit_note)}
        class="link link-primary touch-target"
      >
        {~t"Send"}
      </button>
    </p>
    """
  end

  defp status_tone(:open), do: :warning
  defp status_tone(:paid), do: :success
  defp status_tone(:cancelled), do: :neutral

  defp status_label(:open), do: ~t"Unpaid"
  defp status_label(:paid), do: ~t"Paid"
  defp status_label(:cancelled), do: ~t"Cancelled"

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:mode, fn -> nil end)

    # Saving business details reloads the purchase; its form starts again from what was saved.
    if socket.assigns[:business_saved?] do
      {:ok, socket |> assign(:business_saved?, false) |> assign_business_form() |> assign_create_preview()}
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, purchase: purchase(assigns), invoice: invoice(assigns), credit_note: credit_note(assigns))

    ~H"""
    <div id={@id}>
      <.admin_drawer
        id={"#{@id}-drawer"}
        title={title(@mode, @invoice, @credit_note)}
        on_close={JS.push("close", target: @myself)}
      >
        <%= if @purchase && match?({:create, _}, @mode) do %>
          <.drawer_body>
            <div
              :if={!@purchase.invoiceable?}
              id={"#{@id}-missing"}
              role="alert"
              class="bg-warning/15 border-base-content/12 flex gap-2.5 border px-3 py-2.5 text-sm"
            >
              <.icon name="hero-exclamation-triangle" class="text-warning-content mt-0.5 h-5 w-5 shrink-0" />
              <div>
                <p class="text-warning-content font-semibold">{~t"Not ready to invoice yet."}</p>
                <%= cond do %>
                  <% @purchase.missing_business_details != [] -> %>
                    <p class="mt-0.5">{~t"Still needed for a business customer:"}</p>
                    <ul class="mt-0.5 list-inside list-disc">
                      <li :for={field <- @purchase.missing_business_details}>{business_field_label(field)}</li>
                    </ul>
                  <% !@purchase.buyer_details_complete? -> %>
                    <p class="mt-0.5">{~t"Add the customer's name and email to the order first."}</p>
                  <% true -> %>
                    <p class="mt-0.5">{~t"Only a placed order or a confirmed booking on invoice terms can be invoiced."}</p>
                <% end %>
              </div>
            </div>

            <details
              id={"#{@id}-business"}
              open={@purchase.missing_business_details != []}
              phx-mounted={JS.ignore_attributes(["open"])}
              class="border-base-content/12 border-b pb-4"
            >
              <summary class="link link-primary text-sm">{~t"Business details"}</summary>
              <.form
                for={@business_form}
                id={"#{@id}-business-form"}
                phx-change="validate_business"
                phx-submit="save_business"
                phx-target={@myself}
                class="mt-3 space-y-4"
              >
                <.business_customer_fields form={@business_form} />
                <.button type="submit" variant="secondary" size="sm">{~t"Save business details"}</.button>
              </.form>
            </details>

            <.form
              for={@form}
              id={"#{@id}-form"}
              phx-change="validate"
              phx-submit="create"
              phx-target={@myself}
              class="space-y-4"
            >
              <div class="grid grid-cols-2 items-end gap-x-3 gap-y-4">
                <.input
                  field={@form[:amount]}
                  type="text"
                  inputmode="decimal"
                  label={~t"Amount (€)"}
                  class="input w-full tabular-nums"
                />
                <.input field={@form[:due_date]} type="date" label={~t"Due date"} class="input w-full" />
              </div>
              <p class="text-base-content/75 text-sm">
                {~t"Not yet invoiced: #{amount = Format.currency(Decimal.max(@purchase.uninvoiced_balance, 0), @locale)}"}
              </p>
              <.input
                field={@form[:locale]}
                type="select"
                label={~t"Language"}
                class="select w-full"
                options={Enum.map(Locales.all(), &{Locales.name(&1), &1})}
              />
              <.customer_email
                id={"#{@id}-email"}
                send={@form[:email_customer?]}
                label={~t"Email it to the customer"}
                message={@form[:message]}
                to={@invoice_to}
                preview={@preview}
              />
            </.form>
          </.drawer_body>
          <.drawer_footer>
            <.button type="submit" form={"#{@id}-form"} variant="primary" disabled={!@purchase.invoiceable?}>
              {if sending?(@form), do: ~t"Create and send", else: ~t"Create invoice"}
            </.button>
            <.button type="button" phx-click={JS.exec("phx-hide", to: "##{@id}-drawer")} variant="ghost">
              {~t"Cancel"}
            </.button>
          </.drawer_footer>
        <% end %>

        <.form
          :if={@invoice && match?({:cancel, _}, @mode)}
          for={@cancel_form}
          id={"#{@id}-cancel-form"}
          phx-change="validate_cancel"
          phx-submit="cancel"
          phx-target={@myself}
          class="flex min-h-0 flex-1 flex-col"
        >
          <.drawer_body>
            <p class="tabular-nums">
              {Format.currency(@invoice.amount, @locale)} · {~t"dated #{date = Format.date(@invoice.invoice_date, @locale)}"}
            </p>
            <p class="text-base-content/75 text-sm">
              {~t"A credit note cancels the whole invoice, so it no longer counts as invoiced. If anything is still to pay, create a new invoice afterwards."}
            </p>
            <.input
              field={@cancel_form[:reason]}
              type="textarea"
              rows="2"
              label={~t"Reason (optional)"}
              placeholder={~t"Printed on the credit note, in the invoice's language."}
              class="textarea w-full"
            />
            <.customer_email
              id={"#{@id}-cancel-email"}
              send={@cancel_form[:email_customer?]}
              label={~t"Email the credit note to the customer"}
              message={@cancel_form[:message]}
              to={@invoice.buyer_email}
              preview={@preview}
            />
          </.drawer_body>
          <.drawer_footer>
            <.button type="submit" variant="destructive">
              {if sending?(@cancel_form), do: ~t"Cancel and send", else: ~t"Cancel invoice"}
            </.button>
            <.button type="button" phx-click={JS.exec("phx-hide", to: "##{@id}-drawer")} variant="ghost">
              {~t"Keep invoice"}
            </.button>
          </.drawer_footer>
        </.form>

        <.form
          :if={(@invoice && match?({:send, _}, @mode)) || @credit_note}
          for={@send_form}
          id={"#{@id}-send-form"}
          phx-change="validate_send"
          phx-submit="send"
          phx-target={@myself}
          class="flex min-h-0 flex-1 flex-col"
        >
          <.drawer_body>
            <p :if={@invoice} class="tabular-nums">
              {Format.currency(@invoice.amount, @locale)} · {~t"due #{date = Format.date(@invoice.due_date, @locale)}"}
            </p>
            <p :if={@credit_note} class="tabular-nums">
              {~t"Cancels invoice #{number = @credit_note.invoice.number}"} · {Format.currency(
                Decimal.negate(@credit_note.invoice.amount),
                @locale
              )}
            </p>
            <.customer_email
              id={"#{@id}-send-email"}
              message={@send_form[:message]}
              to={(@invoice || @credit_note.invoice).buyer_email}
              preview={@preview}
            />
          </.drawer_body>
          <.drawer_footer>
            <.button type="submit" variant="primary">
              <.icon name="hero-envelope" class="h-4 w-4" />
              {if @credit_note, do: ~t"Send credit note", else: ~t"Send invoice"}
            </.button>
            <.button type="button" phx-click={JS.exec("phx-hide", to: "##{@id}-drawer")} variant="ghost">
              {~t"Cancel"}
            </.button>
          </.drawer_footer>
        </.form>
      </.admin_drawer>
    </div>
    """
  end

  defp title({:send, _id}, %Invoice{number: number}, _credit_note), do: ~t"Send invoice #{number}"
  defp title({:cancel, _id}, %Invoice{number: number}, _credit_note), do: ~t"Cancel invoice #{number}"
  defp title({:send_credit_note, _id}, _invoice, %CreditNote{number: number}), do: ~t"Send credit note #{number}"
  defp title(_mode, _invoice, _credit_note), do: ~t"Create invoice"

  defp business_field_label(:company_name), do: ~t"Company name"
  defp business_field_label(:business_id), do: ~t"Y-tunnus"
  defp business_field_label(:billing_address), do: ~t"Billing address"

  defp sending?(form), do: form[:email_customer?].value in [true, "true"]

  @impl true
  def handle_event("open_create", %{"purchase_id" => id}, socket) do
    socket = assign(socket, mode: {:create, id})
    purchase = purchase(socket.assigns)

    {:noreply,
     socket
     |> assign(:form, invoice_form(purchase, socket.assigns.current_user))
     |> assign(:invoice_to, purchase_email(purchase))
     |> assign_business_form()
     |> assign_create_preview()
     |> show_drawer()}
  end

  def handle_event("open_send", %{"invoice_id" => id}, socket) do
    socket = assign(socket, mode: {:send, id}, send_form: to_form(%{"message" => ""}, as: :send))

    {:noreply, socket |> assign_send_preview() |> show_drawer()}
  end

  def handle_event("open_send_credit_note", %{"credit_note_id" => id}, socket) do
    socket = assign(socket, mode: {:send_credit_note, id}, send_form: to_form(%{"message" => ""}, as: :send))

    {:noreply, socket |> assign_send_preview() |> show_drawer()}
  end

  def handle_event("open_cancel", %{"invoice_id" => id}, socket) do
    socket = assign(socket, mode: {:cancel, id})

    {:noreply,
     socket
     |> assign(:cancel_form, cancel_form(invoice(socket.assigns), socket.assigns.current_user))
     |> assign_cancel_preview()
     |> show_drawer()}
  end

  def handle_event("validate_cancel", %{"cancel" => params}, socket) do
    {:noreply,
     socket
     |> assign(:cancel_form, AshPhoenix.Form.validate(socket.assigns.cancel_form, params))
     |> assign_cancel_preview()}
  end

  def handle_event("cancel", %{"cancel" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.cancel_form, params: params) do
      {:ok, credit_note} ->
        {:noreply, socket |> hide_drawer() |> changed(cancelled_message(invoice(socket.assigns), credit_note))}

      {:error, form} ->
        {:noreply, assign(socket, :cancel_form, form)}
    end
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, mode: nil, preview: nil)}
  end

  def handle_event("validate", %{"invoice" => params}, socket) do
    {:noreply,
     socket |> assign(:form, AshPhoenix.Form.validate(socket.assigns.form, params)) |> assign_create_preview()}
  end

  def handle_event("create", %{"invoice" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, invoice} ->
        {:noreply, socket |> hide_drawer() |> changed(created_message(invoice))}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("validate_business", %{"business" => params}, socket) do
    {:noreply, assign(socket, :business_form, AshPhoenix.Form.validate(socket.assigns.business_form, params))}
  end

  def handle_event("save_business", %{"business" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.business_form, params: params) do
      {:ok, _purchase} ->
        {:noreply, socket |> assign(:business_saved?, true) |> changed({:success, ~t"Business details saved."})}

      {:error, form} ->
        {:noreply, assign(socket, :business_form, form)}
    end
  end

  def handle_event("validate_send", %{"send" => params}, socket) do
    {:noreply, socket |> assign(:send_form, to_form(params, as: :send)) |> assign_send_preview()}
  end

  def handle_event("send", %{"send" => %{"message" => message}}, %{assigns: %{mode: {:send_credit_note, _}}} = socket) do
    credit_note = credit_note(socket.assigns)

    case Payments.send_credit_note(credit_note, %{message: message}, actor: socket.assigns.current_user) do
      {:ok, _sent} ->
        {:noreply,
         socket |> hide_drawer() |> changed({:success, ~t"Credit note #{number = credit_note.number} emailed."})}

      {:error, _error} ->
        {:noreply, changed(socket, {:error, ~t"Could not email the credit note. Try again in a moment."})}
    end
  end

  def handle_event("send", %{"send" => %{"message" => message}}, socket) do
    invoice = invoice(socket.assigns)

    case Payments.send_invoice(invoice, %{message: message}, actor: socket.assigns.current_user) do
      {:ok, _sent} ->
        {:noreply, socket |> hide_drawer() |> changed({:success, ~t"Invoice #{number = invoice.number} emailed."})}

      {:error, _error} ->
        {:noreply, changed(socket, {:error, ~t"Could not email the invoice. Try again in a moment."})}
    end
  end

  defp created_message(invoice) do
    number = invoice.number

    case invoice.__metadata__[:emailed?] do
      true -> {:success, ~t"Invoice #{number} created and emailed."}
      false -> {:error, ~t"Invoice #{number} created, but it could not be emailed. Send it from the invoice list."}
      nil -> {:success, ~t"Invoice #{number} created."}
    end
  end

  defp cancelled_message(invoice, credit_note) do
    {invoice, number} = {invoice.number, credit_note.number}

    case credit_note.__metadata__[:emailed?] do
      true ->
        {:success, ~t"Invoice #{invoice} cancelled with credit note #{number}, emailed to the customer."}

      false ->
        {:error,
         ~t"Invoice #{invoice} cancelled with credit note #{number}, but it could not be emailed. Send it from the invoice list."}

      nil ->
        {:success, ~t"Invoice #{invoice} cancelled with credit note #{number}."}
    end
  end

  defp changed(socket, flash) do
    send(self(), {__MODULE__, flash})
    socket
  end

  defp show_drawer(socket), do: push_event(socket, "js-exec", %{to: "##{socket.assigns.id}-drawer", attr: "phx-show"})
  defp hide_drawer(socket), do: push_event(socket, "js-exec", %{to: "##{socket.assigns.id}-drawer", attr: "phx-hide"})

  defp purchase(%{mode: {:create, id}, purchases: purchases}), do: Enum.find(purchases, &(&1.id == id))
  defp purchase(_assigns), do: nil

  defp invoice(%{mode: {mode, id}, purchases: purchases}) when mode in [:send, :cancel] do
    purchases |> Enum.flat_map(& &1.invoices) |> Enum.find(&(&1.id == id))
  end

  defp invoice(_assigns), do: nil

  defp credit_note(%{mode: {:send_credit_note, id}, purchases: purchases}) do
    purchases
    |> Enum.flat_map(& &1.invoices)
    |> Enum.find_value(fn invoice ->
      if invoice.credit_note && invoice.credit_note.id == id, do: %{invoice.credit_note | invoice: invoice}
    end)
  end

  defp credit_note(_assigns), do: nil

  defp purchase_email(%CourseRegistration{email: email}), do: email
  defp purchase_email(order), do: order.customer_email

  defp invoice_form(purchase, actor) do
    key = if match?(%CourseRegistration{}, purchase), do: "course_registration_id", else: "order_id"
    uninvoiced = purchase.uninvoiced_balance

    Invoice
    |> AshPhoenix.Form.for_create(:create,
      actor: actor,
      as: "invoice",
      params: %{
        "amount" => if(Decimal.positive?(uninvoiced), do: Decimal.to_string(uninvoiced, :normal), else: ""),
        "due_date" => Date.to_iso8601(Invoice.default_due_date()),
        "locale" => purchase.locale,
        "email_customer?" => "true",
        "message" => ""
      },
      transform_params: fn _form, params, _type -> Map.put(params, key, purchase.id) end
    )
    |> to_form()
  end

  # Emailing starts ticked only for an invoice the customer was sent: a credit
  # note for one they never had would only puzzle them.
  defp cancel_form(invoice, actor) do
    CreditNote
    |> AshPhoenix.Form.for_create(:create,
      actor: actor,
      as: "cancel",
      params: %{"reason" => "", "email_customer?" => to_string(!!invoice.sent_at), "message" => ""},
      transform_params: fn _form, params, _type -> Map.put(params, "invoice_id", invoice.id) end
    )
    |> to_form()
  end

  defp assign_business_form(socket) do
    form =
      socket.assigns
      |> purchase()
      |> AshPhoenix.Form.for_update(:update_business_details, actor: socket.assigns.current_user, as: "business")
      |> to_form()

    assign(socket, :business_form, form)
  end

  defp assign_create_preview(socket) do
    form = socket.assigns.form

    preview =
      if sending?(form) do
        params = AshPhoenix.Form.params(form.source)
        Preview.build_new_invoice(purchase(socket.assigns), params, params["message"])
      end

    assign(socket, :preview, preview)
  end

  defp assign_cancel_preview(socket) do
    form = socket.assigns.cancel_form
    preview = if sending?(form), do: Preview.build_credit_note(invoice(socket.assigns), form[:message].value)

    assign(socket, :preview, preview)
  end

  defp assign_send_preview(socket) do
    message = socket.assigns.send_form[:message].value

    preview =
      case socket.assigns.mode do
        {:send_credit_note, _id} -> Preview.build_credit_note(credit_note(socket.assigns), message)
        {:send, _id} -> Preview.build_invoice(invoice(socket.assigns), message)
      end

    assign(socket, :preview, preview)
  end
end

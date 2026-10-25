defmodule EdenflowersWeb.Admin.Drawers do
  @moduledoc """
  The drawers Jennie opens on an order or a booking: recording a payment,
  refunding, cancelling, and emailing the customer. `admin_drawer` gives them
  all the same width and header.
  """

  use EdenflowersWeb, :html

  alias EdenflowersWeb.Admin.OrderLog

  attr :title, :string, required: true
  attr :submit_label, :string, required: true
  attr :keep_label, :string, required: true
  attr :form, :any, default: nil
  attr :error, :string, default: nil
  attr :email, :string, default: nil, doc: "the customer's address, or nil when they have none"
  attr :locale, :string, required: true
  attr :preview, Swoosh.Email, default: nil
  attr :swedish_toggle?, :boolean, default: false, doc: "whether the customer reads something other than Swedish"

  @doc """
  Cancels an order or a booking: how much to refund, and whether to email
  the customer, with an optional message. Takes `PaymentActions.cancel_form/1`. Sends
  `validate_cancel` and `submit_cancel` with `cancel` params, and
  `close_cancel` when it closes.
  """
  def cancel_drawer(assigns) do
    ~H"""
    <.admin_drawer id="cancel-drawer" title={@title} on_close={JS.push("close_cancel")}>
      <.form
        :if={@form}
        for={@form}
        id="cancel-form"
        phx-change="validate_cancel"
        phx-submit="submit_cancel"
        class="flex min-h-0 flex-1 flex-col"
      >
        <.drawer_body>
          <p :if={@error} role="alert" class="text-error text-sm">{@error}</p>
          <input type="hidden" name={@form[:held].name} value={@form[:held].value} />
          <div :if={Decimal.positive?(Decimal.new(@form[:held].value))} class="space-y-2">
            <.input
              field={@form[:refund]}
              type="text"
              inputmode="decimal"
              label={~t"Amount to refund (€)"}
              class="input w-full tabular-nums"
            />
            <p class="text-base-content/75 text-sm">
              {~t"Paid #{amount = Edenflowers.Format.currency(Decimal.new(@form[:held].value), @locale)}. Card payments go back through Stripe; anything paid in person you hand back yourself. Whatever you don't refund you keep."}
            </p>
          </div>
          <.customer_email
            :if={@email}
            id="cancel-email"
            send={@form[:email_customer]}
            label={~t"Email the customer"}
            message={@form[:message]}
            to={@email}
            preview={@preview}
            in_swedish={@swedish_toggle? && @form[:in_swedish]}
          />
          <p :if={!@email} class="text-base-content/75 text-sm">
            {~t"There's no email address, so the customer won't be emailed."}
          </p>
        </.drawer_body>
        <.drawer_footer>
          <.button type="submit" variant="destructive">{@submit_label}</.button>
          <.button
            type="button"
            phx-click={JS.exec("phx-hide", to: "#cancel-drawer") |> JS.push("close_cancel")}
            variant="ghost"
          >{@keep_label}</.button>
        </.drawer_footer>
      </.form>
    </.admin_drawer>
    """
  end

  attr :id, :string, required: true
  attr :send, Phoenix.HTML.FormField, default: nil, doc: "the tick box, or nil when sending is the form's whole job"
  attr :label, :string, default: nil, doc: "the tick box's label"
  attr :message, Phoenix.HTML.FormField, required: true
  attr :to, :string, default: nil, doc: "the customer's address, when the form already knows it"
  attr :preview, Swoosh.Email, default: nil, doc: "what would be sent, from `Edenflowers.Email.Preview`"
  attr :in_swedish, Phoenix.HTML.FormField, default: nil, doc: "the toggle to preview it in Swedish, if not already"
  slot :inner_block, doc: "more choices about the email, like whether to attach the photo"

  @doc """
  The tick box, message box and preview beside every email one of Jennie's
  actions sends (ADR 0006). The message box and preview show only while the
  email is ticked.
  """
  def customer_email(assigns) do
    assigns = assign(assigns, :sending?, is_nil(assigns.send) or assigns.send.value in [true, "true"])

    ~H"""
    <div id={@id} class="space-y-2">
      <.input :if={@send} field={@send} id={"#{@id}-send"} type="checkbox" label={@label} />
      <div class={["space-y-3", @send && "ml-7"]}>
        <p :if={@to} class="text-base-content/75 break-all text-sm">{~t"To: #{email = @to}"}</p>
        {render_slot(@inner_block)}
        <.input
          :if={@sending?}
          field={@message}
          id={"#{@id}-message"}
          type="textarea"
          rows="3"
          label={~t"Message to the customer (optional)"}
          placeholder={~t"Goes after the first line of the email."}
          class="textarea w-full"
        />
        <%= if @preview && @sending? do %>
          <.input
            :if={@in_swedish}
            field={@in_swedish}
            id={"#{@id}-in-swedish"}
            type="checkbox"
            label={~t"Preview in Swedish"}
          />
          <details class="sm:hidden">
            <summary class="link link-primary text-sm">{~t"Preview the email"}</summary>
            <.email_preview email={@preview} />
          </details>
          <div id={"#{@id}-preview"} class="hidden sm:block">
            <.email_preview email={@preview} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :email, Swoosh.Email, required: true

  defp email_preview(assigns) do
    ~H"""
    <section
      aria-label={~t"Email preview"}
      class="border-base-content/12 bg-base-200/40 mt-3 space-y-3 rounded-lg border p-3 text-sm"
    >
      <h3 class="eyebrow text-base-content/75">{~t"Preview"}</h3>
      <p class="font-semibold">{@email.subject}</p>
      <p class="whitespace-pre-line break-words">{@email.text_body}</p>
      <p :if={@email.attachments != []} class="text-base-content/75">
        {~t"Attached: #{files = Enum.map_join(@email.attachments, ", ", & &1.filename)}"}
      </p>
    </section>
    """
  end

  attr :form, :any, default: nil
  attr :title, :string, default: nil
  attr :submit_label, :string, default: nil
  attr :to, :string, default: nil
  attr :last_sent, :string, default: nil, doc: "when this email last went, if it has"
  attr :preview, Swoosh.Email, default: nil
  attr :swedish_toggle?, :boolean, default: false, doc: "whether the customer reads something other than Swedish"

  @doc """
  Sends one email from a menu item or button, with Jennie's message. Sends
  `validate_email` and `send_email` with `email` params, and `close_email`
  when it closes.
  """
  def email_drawer(assigns) do
    ~H"""
    <.admin_drawer id="email-drawer" title={@title || ""} on_close={JS.push("close_email")}>
      <.form
        :if={@form}
        for={@form}
        id="email-form"
        phx-change="validate_email"
        phx-submit="send_email"
        class="flex min-h-0 flex-1 flex-col"
      >
        <.drawer_body>
          <p :if={@last_sent} class="text-base-content/75 text-sm">{~t"Last sent #{time = @last_sent}."}</p>
          <.customer_email
            id="email-drawer-email"
            message={@form[:message]}
            to={@to}
            preview={@preview}
            in_swedish={@swedish_toggle? && @form[:in_swedish]}
          />
        </.drawer_body>
        <.drawer_footer>
          <.button type="submit" variant="primary">
            <.icon name="hero-envelope" class="h-4 w-4" /> {@submit_label}
          </.button>
          <.button
            type="button"
            phx-click={JS.exec("phx-hide", to: "#email-drawer") |> JS.push("close_email")}
            variant="ghost"
          >{~t"Cancel"}</.button>
        </.drawer_footer>
      </.form>
    </.admin_drawer>
    """
  end

  attr :id, :string, required: true
  attr :record, :map, required: true, doc: "an order, with `balance` loaded"
  attr :locale, :string, required: true
  attr :params, :map, default: %{}, doc: "the payment form as Jennie has filled it in so far"
  attr :receipt_email?, :boolean, default: false, doc: "whether the customer can be emailed a receipt"
  attr :preview, Swoosh.Email, default: nil
  attr :swedish_toggle?, :boolean, default: false, doc: "whether the customer reads something other than Swedish"

  @doc """
  Records money Jennie took herself. Sends `record_payment` with `payment`
  params and the record's id as `record_id`, and `change_payment` with
  `payment` params as the form is filled in.
  """
  def record_payment_form(assigns) do
    form =
      %{
        "payment_method" => "zettle",
        "amount" => Decimal.to_string(assigns.record.balance, :normal),
        "email_receipt" => "false"
      }
      |> Map.merge(assigns.params)
      |> to_form(as: :payment)

    assigns = assign(assigns, form: form)

    ~H"""
    <.form for={@form} id={"#{@id}-form"} phx-change="change_payment" phx-submit="record_payment" class="space-y-4">
      <input type="hidden" name="record_id" value={@record.id} />
      <div class="grid grid-cols-2 items-end gap-x-3 gap-y-4">
        <.input
          field={@form[:payment_method]}
          id={"#{@id}-method"}
          type="select"
          label={~t"How"}
          class="select w-full"
          options={payment_method_options()}
        />
        <.input
          field={@form[:amount]}
          id={"#{@id}-amount"}
          type="text"
          inputmode="decimal"
          label={~t"Amount (€)"}
          class="input w-full tabular-nums"
        />
      </div>
      <.customer_email
        :if={@receipt_email?}
        id={"#{@id}-email"}
        send={@form[:email_receipt]}
        label={~t"Email the customer a receipt"}
        message={@form[:message]}
        preview={@preview}
        in_swedish={@swedish_toggle? && @form[:in_swedish]}
      />
      <.button
        type="submit"
        variant="primary"
        data-confirm={~t"Record this payment? A mistake can be undone afterwards."}
      >
        {~t"Record payment"}
      </.button>
    </.form>
    """
  end

  @doc "Every way Jennie records money herself; Stripe records its own."
  def payment_method_options do
    Edenflowers.Payments.PaymentMethod.values()
    |> List.delete(:stripe)
    |> Enum.map(&{OrderLog.payment_method_label(&1), &1})
  end

  @doc "Asks before undoing a payment Jennie recorded, naming it."
  def undo_confirmation(payment, locale) do
    amount = Edenflowers.Format.currency(Decimal.abs(payment.amount), locale)
    how = OrderLog.payment_method_label(payment.method)

    if Decimal.negative?(payment.amount),
      do: ~t"Undo the #{amount} refund by #{how}? This records the opposite amount.",
      else: ~t"Undo the #{amount} payment by #{how}? This records the opposite amount."
  end

  attr :id, :string, required: true

  attr :record, :map,
    required: true,
    doc: "an order or booking, with `balance`, `refund_methods` and `default_refund_method` loaded"

  attr :email, :string, default: nil, doc: "the customer's address, or nil when they have none"
  attr :locale, :string, required: true
  attr :params, :map, default: %{}, doc: "the form as Jennie has filled it in so far"
  attr :preview, Swoosh.Email, default: nil
  attr :swedish_toggle?, :boolean, default: false, doc: "whether the customer reads something other than Swedish"

  @doc """
  Hands money back, with or without cancelling: what's owed back, or more for
  an unhappy customer. Starts at what's owed back, if anything. Sends `refund`
  with `refund` params and the record's id as `record_id`, and
  `change_refund` as the form is filled in, so the confirmation can name the
  amount.
  """
  def refund_form(assigns) do
    owed_back = Decimal.max(Decimal.negate(assigns.record.balance), 0)

    form =
      %{
        "how" => to_string(assigns.record.default_refund_method),
        "amount" => if(Decimal.positive?(owed_back), do: Decimal.to_string(owed_back, :normal), else: ""),
        "note" => "",
        "email_customer" => "true"
      }
      |> Map.merge(assigns.params)
      |> to_form(as: :refund)

    how_options = Enum.map(assigns.record.refund_methods, &{OrderLog.payment_method_label(&1), &1})
    assigns = assign(assigns, form: form, how_options: how_options)

    ~H"""
    <.form for={@form} id={"#{@id}-form"} phx-change="change_refund" phx-submit="refund" class="space-y-4">
      <input type="hidden" name="record_id" value={@record.id} />
      <div class="grid grid-cols-2 items-end gap-x-3 gap-y-4">
        <.input
          field={@form[:amount]}
          id={"#{@id}-amount"}
          type="text"
          inputmode="decimal"
          label={~t"Amount (€)"}
          class="input w-full tabular-nums"
        />
        <.input
          field={@form[:how]}
          id={"#{@id}-how"}
          type="select"
          label={~t"How"}
          class="select w-full"
          options={@how_options}
        />
      </div>
      <p :if={@form[:how].value != "stripe"} class="text-base-content/75 text-sm">
        {~t"Records money you have already handed back."}
      </p>
      <.customer_email
        :if={@email}
        id={"#{@id}-email"}
        send={@form[:email_customer]}
        label={~t"Email the customer"}
        message={@form[:note]}
        to={@email}
        preview={@preview}
        in_swedish={@swedish_toggle? && @form[:in_swedish]}
      />
      <.button
        type="submit"
        variant="primary"
        data-confirm={refund_confirmation(@form[:amount].value, @form[:how].value, @locale)}
      >
        {~t"Refund"}
      </.button>
    </.form>
    """
  end

  defp refund_confirmation(amount, how, locale) do
    with {amount, ""} <- Decimal.parse(String.replace(amount || "", ",", ".")),
         true <- Decimal.positive?(amount) do
      amount = Edenflowers.Format.currency(amount, locale)

      if how == "stripe",
        do: ~t"Refund #{amount} to the customer's card with Stripe?",
        else: ~t"Record #{amount} handed back to the customer?"
    else
      _invalid -> nil
    end
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :on_close, JS, default: %JS{}, doc: "runs after the drawer hides, like telling the server"
  slot :inner_block, required: true

  @doc """
  The admin's right-hand drawer: a titled panel with a close button, so every
  admin drawer has one width and one header. Put the content in `drawer_body`
  and any buttons in `drawer_footer`; a form can wrap both.
  Open it with `JS.exec("phx-show", to: "#id")` or the `js-exec` event.
  """
  def admin_drawer(assigns) do
    ~H"""
    <.drawer
      id={@id}
      placement="right"
      label={@title}
      class="bg-base-100 border-base-content/12 w-[88vw] flex h-full flex-col border-l sm:w-[28rem]"
    >
      <header class="border-base-content/12 flex shrink-0 items-center justify-between gap-4 border-b p-4">
        <h2 class="text-lg font-semibold">{@title}</h2>
        <.icon_button
          phx-click={JS.exec("phx-hide", to: "##{@id}") |> JS.concat(@on_close)}
          size="sm"
          aria_label={~t"Close"}
        >
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </.icon_button>
      </header>
      {render_slot(@inner_block)}
    </.drawer>
    """
  end

  slot :inner_block, required: true

  @doc "An `admin_drawer`'s content, which scrolls under the header."
  def drawer_body(assigns) do
    ~H"""
    <div class="flex-1 space-y-5 overflow-y-auto overscroll-contain p-4">
      {render_slot(@inner_block)}
    </div>
    """
  end

  slot :inner_block, required: true

  @doc "An `admin_drawer`'s buttons, pinned to its bottom."
  def drawer_footer(assigns) do
    ~H"""
    <div class="border-base-content/12 flex shrink-0 flex-wrap gap-2 border-t p-4">
      {render_slot(@inner_block)}
    </div>
    """
  end
end

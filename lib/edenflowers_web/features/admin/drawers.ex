defmodule EdenflowersWeb.Admin.Drawers do
  @moduledoc """
  The drawers Jennie opens on an order or a booking: recording a payment,
  refunding, cancelling, and emailing the customer. `admin_drawer` gives them
  all the same width and header.
  """

  use EdenflowersWeb, {:html, gettext_domain: "admin"}

  alias EdenflowersWeb.Admin.OrderLog
  alias EdenflowersWeb.Admin.PaymentActions

  attr :title, :string, required: true
  attr :submit_label, :string, required: true
  attr :keep_label, :string, required: true
  attr :form, :any, default: nil
  attr :payable, :any, default: nil, doc: "the order or booking, from `PaymentActions.load_for_cancel/1`"
  attr :email, :string, default: nil, doc: "the customer's address, or nil when they have none"
  attr :locale, :string, required: true
  attr :preview, Swoosh.Email, default: nil

  @doc """
  Cancels an order or a booking: the cancellation charge to keep, Jennie's
  reason for her records, and whether to email the customer, as she
  rewrites it if she likes. Takes `PaymentActions.cancel_form/2`. Sends
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
          <.refusal form={@form} />
          <div :if={Decimal.positive?(@payable.total_due)} class="space-y-2">
            <.input
              field={@form[:cancellation_charge]}
              value={@form.source.raw_params["cancellation_charge"]}
              type="text"
              inputmode="decimal"
              label={~t"Cancellation charge (€)"}
              class="input w-full tabular-nums"
            />
            <p class="text-base-content/75 text-sm">
              {~t"Paid #{paid = Edenflowers.Format.currency(Decimal.max(@payable.amount_held, 0), @locale)} of #{total = Edenflowers.Format.currency(Decimal.max(@payable.total_due, 0), @locale)}."}
              <%= case cancel_outcome(@payable, @form[:cancellation_charge].value) do %>
                <% {:refund, amount} -> %>
                  {~t"#{amount = Edenflowers.Format.currency(amount, @locale)} will be refunded."}
                <% {:collect, amount} -> %>
                  {~t"#{amount = Edenflowers.Format.currency(amount, @locale)} left for the customer to pay."}
                <% :settled -> %>
                  {~t"Nothing to refund."}
                <% nil -> %>
              <% end %>
            </p>
            <p
              :if={match?({:refund, _}, cancel_outcome(@payable, @form[:cancellation_charge].value))}
              class="text-base-content/75 text-sm"
            >
              {~t"Card payments are refunded through Stripe, and anything paid in person you hand back yourself."}
            </p>
          </div>
          <.input
            field={@form[:cancellation_reason]}
            id="cancel-reason"
            type="textarea"
            rows="2"
            label={~t"Reason (for your records)"}
            class="textarea w-full"
          />
          <.customer_email
            :if={@email}
            id="cancel-email"
            send={@form[:email_customer?]}
            label={~t"Email the customer"}
            form={@form}
            to={@email}
            preview={@preview}
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

  # What cancelling with the charge typed so far refunds or leaves to collect,
  # as the cancel action works it out, or nil while the charge isn't an amount.
  defp cancel_outcome(payable, charge) do
    with {:ok, charge} <- Ash.Type.cast_input(Edenflowers.Types.Price, charge),
         charge = charge || payable.default_cancellation_charge,
         false <- Decimal.negative?(charge) do
      money = Edenflowers.Payments.Changes.Cancel.money(payable, charge)
      refund = money.refunded |> Decimal.add(money.back_on_voucher) |> Decimal.add(money.to_return)

      cond do
        Decimal.positive?(refund) -> {:refund, refund}
        Decimal.positive?(money.to_collect) -> {:collect, money.to_collect}
        true -> :settled
      end
    else
      _ -> nil
    end
  end

  attr :id, :string, required: true
  attr :send, Phoenix.HTML.FormField, default: nil, doc: "the tick box, or nil when sending is the form's whole job"
  attr :label, :string, default: nil, doc: "the tick box's label"
  attr :form, Phoenix.HTML.Form, required: true, doc: "the form holding `edit_email`, `subject` and `body`"
  attr :to, :string, default: nil, doc: "the customer's address, when the form already knows it"
  attr :preview, Swoosh.Email, default: nil, doc: "what would be sent, from `Edenflowers.Email.Preview`"
  attr :collapse_preview?, :boolean, default: false
  slot :inner_block, doc: "more choices about the email, like whether to attach the photo"

  @doc """
  The tick box and preview beside every email one of Jennie's actions sends
  (ADR 0006), and the tick box to rewrite it. Rewriting swaps the preview
  for its subject and text to edit; unticking
  it goes back to the email as built. Read what she wrote with
  `email_edits/1`. The preview shows only while the email is ticked.
  """
  def customer_email(assigns) do
    assigns =
      assign(assigns,
        sending?: is_nil(assigns.send) or assigns.send.value in [true, "true"],
        editing?: assigns.form[:edit_email].value in [true, "true"]
      )

    ~H"""
    <div id={@id} class="space-y-2">
      <.input :if={@send} field={@send} id={"#{@id}-send"} type="checkbox" label={@label} />
      <div class={["space-y-3", @send && "ml-7"]}>
        <p :if={@to} class="text-base-content/75 break-all text-sm">{~t"To: #{email = @to}"}</p>
        {render_slot(@inner_block)}
        <.input
          :if={@preview && @sending?}
          field={@form[:edit_email]}
          id={"#{@id}-edit"}
          type="checkbox"
          label={~t"Edit the email"}
        />
        <div :if={@preview && @sending? && @editing?} id={"#{@id}-editor"} class="space-y-3">
          <.input
            field={@form[:subject]}
            id={"#{@id}-subject"}
            value={@form[:subject].value || @preview.subject}
            type="text"
            label={~t"Subject"}
            phx-debounce="400"
            required
            class="input w-full"
          />
          <.input
            field={@form[:body]}
            id={"#{@id}-body"}
            value={@form[:body].value || @preview.text_body}
            type="textarea"
            rows="16"
            label={~t"Email"}
            phx-debounce="400"
            required
            class="textarea w-full"
          />
          <p :if={@preview.attachments != []} class="text-base-content/75 text-sm">
            {~t"Attached: #{files = Enum.map_join(@preview.attachments, ", ", & &1.filename)}"}
          </p>
        </div>
        <%= if @preview && @sending? && !@editing? do %>
          <details
            id={"#{@id}-preview-toggle"}
            phx-mounted={JS.ignore_attributes(["open"])}
            class={!@collapse_preview? && "sm:hidden"}
          >
            <summary class="link link-primary text-sm">{~t"Preview the email"}</summary>
            <.email_preview email={@preview} />
          </details>
          <div :if={!@collapse_preview?} id={"#{@id}-preview"} class="hidden sm:block">
            <.email_preview email={@preview} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  The subject and text Jennie rewrote in a `customer_email`, as the
  `subject` and `body` arguments of the action that sends it, or nothing to
  send it as built.
  """
  def email_edits(%{"edit_email" => "true"} = params), do: %{subject: params["subject"], body: params["body"]}
  def email_edits(_params), do: %{}

  @doc """
  `email_edits/1` as an AshPhoenix form's `transform_params`: the action gets
  the `subject` and `body` only while "Edit the email" is ticked, which stays
  a param of the form alone.
  """
  def keep_email_edits(_form, %{"edit_email" => "true"} = params, _action), do: params
  def keep_email_edits(_form, params, _action), do: Map.drop(params, ["subject", "body"])

  attr :form, Phoenix.HTML.Form, required: true

  @doc """
  Why a drawer's action was refused, when none of its inputs shows it: an
  error naming no field, or one the drawer has no input for, like a credit
  note refused for its invoice's sake.
  """
  def refusal(assigns) do
    assigns = assign(assigns, :message, refusal_message(assigns.form.source))

    ~H"""
    <p :if={@message} role="alert" class="text-error text-sm">{@message}</p>
    """
  end

  defp refusal_message(%{errors: true} = form) do
    shown = form |> AshPhoenix.Form.params() |> Map.keys()
    errors = AshPhoenix.Form.errors(form)

    cond do
      message = Enum.find_value(errors, fn {field, message} -> to_string(field) not in shown && message end) ->
        message

      errors == [] ->
        unformatted_message(AshPhoenix.Form.raw_errors(form))

      true ->
        nil
    end
  end

  defp refusal_message(_form), do: nil

  # A change's own `add_error(changeset, message)` names no fields, so AshPhoenix
  # leaves it out of the form's errors. Anything else, like a database failure,
  # has no words for Jennie.
  defp unformatted_message([]), do: nil

  defp unformatted_message(errors) do
    Enum.find_value(errors, ~t"Something went wrong. Try again in a moment.", fn
      %Ash.Error.Changes.InvalidChanges{message: message} when is_binary(message) -> message
      _error -> nil
    end)
  end

  @doc """
  `failure`, the flash for an action Jennie ran from a button, followed by
  why the action refused in its own words, when it has some for her: a
  database failure has none.
  """
  def refusal_text(error, failure) do
    case error |> Ash.Error.to_error_class() |> Map.get(:errors, []) |> Enum.find_value(&error_text/1) do
      nil ->
        failure

      reason ->
        gettext_comment(
          "%{failure} is a line like \"Could not remove the seat\", its period dropped. %{reason} is the " <>
            "refusal in English, like \"cancel the booking to remove its last seat\"."
        )

        ~t"#{failure = String.trim_trailing(failure, ".")}: #{reason}."
    end
  end

  defp error_text(%Ash.Error.Changes.InvalidChanges{message: message}) when is_binary(message), do: message

  defp error_text(error) do
    with impl when impl != nil <- AshPhoenix.FormData.Error.impl_for(error),
         [{_field, message, vars} | _] <- error |> AshPhoenix.FormData.Error.to_form_error() |> List.wrap() do
      translate_error({message, vars})
    else
      _no_words -> nil
    end
  end

  attr :email, Swoosh.Email, required: true

  def email_preview(assigns) do
    ~H"""
    <section
      aria-label={~t"Email preview"}
      class="border-base-content/12 bg-base-200/40 mt-3 space-y-3 border p-3 text-sm"
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

  @doc """
  Sends one email from a menu item or button, as Jennie rewrites it if she likes. Sends
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
            form={@form}
            to={@to}
            preview={@preview}
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

  attr :record, :map,
    required: true,
    doc: "an order or booking, with `balance` loaded"

  attr :locale, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true, doc: "from `PaymentActions.payment_form/3`"
  attr :receipt_email?, :boolean, default: false, doc: "whether the customer can be emailed a receipt"
  attr :preview, Swoosh.Email, default: nil

  @doc """
  Records money Jennie took herself. Sends `record_payment` with `payment`
  params and the record's id as `record_id`, and `change_payment` with
  `payment` params as the form is filled in.

  """
  def record_payment_form(assigns) do
    voucher_sale? = PaymentActions.voucher_sale?(assigns.record)

    assigns =
      assign(assigns,
        voucher?: assigns.form.source.action == :pay_with_gift_voucher,
        voucher_sale?: voucher_sale?,
        voucher_part_paid?:
          voucher_sale? and
            not PaymentActions.pays_off_voucher?(assigns.record, assigns.form.source.raw_params["amount"])
      )

    ~H"""
    <.form for={@form} id={"#{@id}-form"} phx-change="change_payment" phx-submit="record_payment" class="space-y-4">
      <input type="hidden" name="record_id" value={@record.id} />
      <.refusal form={@form} />
      <div class="grid grid-cols-2 items-end gap-x-3 gap-y-4">
        <.input
          field={@form[:payment_method]}
          id={"#{@id}-method"}
          type="select"
          label={~t"Payment method"}
          required
          class="select w-full"
          options={payment_method_options(@record)}
        />
        <.input
          :if={not @voucher?}
          field={@form[:amount]}
          value={@form.source.raw_params["amount"]}
          id={"#{@id}-amount"}
          type="text"
          inputmode="decimal"
          label={~t"Amount received (€)"}
          required
          class="input w-full tabular-nums"
        />
        <.input
          :if={@voucher?}
          field={@form[:code]}
          id={"#{@id}-code"}
          type="text"
          autocomplete="off"
          inputmode="numeric"
          phx-hook="VoucherCode"
          spellcheck="false"
          label={~t"Gift voucher code"}
          required
          class="input w-full tabular-nums"
        />
      </div>
      <.customer_email
        :if={@receipt_email? and not @voucher? and not @voucher_part_paid?}
        id={"#{@id}-email"}
        send={@form[:email_receipt?]}
        label={if @voucher_sale?, do: ~t"Email gift voucher and receipt", else: ~t"Email the customer a receipt"}
        form={@form}
        preview={@preview}
      />
      <p :if={@receipt_email? and @voucher_part_paid?} id={"#{@id}-voucher-later"} class="text-base-content/75 text-sm">
        {~t"The gift voucher and receipt can be emailed once it's paid in full."}
      </p>
      <.button
        type="submit"
        variant="primary"
        data-confirm={
          if @voucher?,
            do: ~t"Pay from this gift voucher? A voucher payment can't be undone.",
            else: ~t"Record this payment? A mistake can be undone afterwards."
        }
      >
        {~t"Record payment"}
      </.button>
    </.form>
    """
  end

  @doc """
  Every way Jennie records money herself, a Gift voucher by its code; Stripe
  records its own. Not a Gift voucher on an order that doesn't accept one, a
  Gift voucher sale. A course booking always does.
  """
  def payment_method_options(record) do
    excluded = if Map.get(record, :accepts_gift_voucher?, true), do: [:stripe], else: [:stripe, :voucher]

    Edenflowers.Payments.PaymentMethod.values()
    |> Kernel.--(excluded)
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
  attr :form, Phoenix.HTML.Form, required: true, doc: "from `PaymentActions.refund_form/2`"
  attr :preview, Swoosh.Email, default: nil

  @doc """
  Hands money back, with or without cancelling: what's owed back, or more for
  an unhappy customer. Starts at what's owed back, if anything. Sends `refund`
  with `refund` params and the record's id as `record_id`, and
  `change_refund` as the form is filled in, so the confirmation can name the
  amount.
  """
  def refund_form(assigns) do
    how_options = Enum.map(assigns.record.refund_methods, &{OrderLog.payment_method_label(&1), &1})
    assigns = assign(assigns, :how_options, how_options)

    ~H"""
    <.form for={@form} id={"#{@id}-form"} phx-change="change_refund" phx-submit="refund" class="space-y-4">
      <input type="hidden" name="record_id" value={@record.id} />
      <.refusal form={@form} />
      <div class="grid grid-cols-2 items-end gap-x-3 gap-y-4">
        <.input
          field={@form[:amount]}
          value={@form.source.raw_params["amount"]}
          id={"#{@id}-amount"}
          type="text"
          inputmode="decimal"
          label={~t"Amount (€)"}
          required
          class="input w-full tabular-nums"
        />
        <.input
          field={@form[:payment_method]}
          id={"#{@id}-how"}
          type="select"
          label={~t"How"}
          required
          class="select w-full"
          options={@how_options}
        />
      </div>
      <p :if={to_string(@form[:payment_method].value) != "stripe"} class="text-base-content/75 text-sm">
        {~t"Records money you have already handed back."}
      </p>
      <.input
        field={@form[:note]}
        id={"#{@id}-note"}
        type="text"
        label={~t"Note (for your records)"}
        class="input w-full"
      />
      <.customer_email
        :if={@email}
        id={"#{@id}-email"}
        send={@form[:email_customer?]}
        label={~t"Email the customer"}
        form={@form}
        to={@email}
        preview={@preview}
      />
      <.button
        type="submit"
        variant="primary"
        data-confirm={refund_confirmation(@form[:amount].value, @form[:payment_method].value, @locale)}
      >
        {~t"Refund"}
      </.button>
    </.form>
    """
  end

  defp refund_confirmation(amount, how, locale) do
    with {:ok, %Decimal{} = amount} <- Ash.Type.cast_input(Edenflowers.Types.Price, amount),
         true <- Decimal.positive?(amount) do
      amount = Edenflowers.Format.currency(amount, locale)

      if to_string(how) == "stripe",
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

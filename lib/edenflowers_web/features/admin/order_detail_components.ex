defmodule EdenflowersWeb.Admin.OrderDetailComponents do
  @moduledoc """
  The order page's drawers, queue nav and menus, with the view helpers they need.
  """

  use EdenflowersWeb, :html

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.PhotoUpload, only: [photo_input: 1]

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias EdenflowersWeb.Admin.OrderLog

  attr :order, Order, required: true
  attr :mode, :atom, required: true, values: [:settle, :refund]
  attr :error, :string, default: nil
  attr :payment_params, :map, required: true
  attr :refund_params, :map, required: true
  attr :locale, :string, required: true
  attr :preview, Swoosh.Email, default: nil

  def settlement_drawer(assigns) do
    ~H"""
    <.admin_drawer id="settlement-drawer" title={settlement_title(@order, @mode)}>
      <.drawer_body>
        <div class="space-y-1">
          <p :if={@order.customer_name} class="text-base-content font-medium">{@order.customer_name}</p>
          <p class="text-base-content/75 text-sm tabular-nums">{@order.order_reference}</p>
        </div>
        <dl class="divide-base-content/12 border-base-content/12 divide-y border-y text-sm tabular-nums">
          <div class="flex justify-between gap-4 py-2">
            <dt class="text-base-content/75">{~t"Total"}</dt>
            <dd>{Format.currency(@order.grand_total, @locale)}</dd>
          </div>
          <div class="flex justify-between gap-4 py-2">
            <dt class="text-base-content/75">{~t"Paid"}</dt>
            <dd>{Format.currency(@order.amount_paid, @locale)}</dd>
          </div>
          <div :if={not @order.settled?} class="flex justify-between gap-4 py-2">
            <dt class="text-base-content/75">{if @order.to_collect?, do: ~t"To collect", else: ~t"To refund"}</dt>
            <dd class="font-semibold">{Format.currency(Decimal.abs(@order.balance), @locale)}</dd>
          </div>
        </dl>
        <p :if={@error} role="alert" class="text-error text-sm">{@error}</p>
        <.refund_form
          :if={@mode == :refund and @order.refundable?}
          id="order-refund"
          record={@order}
          email={@order.customer_email}
          locale={@locale}
          params={@refund_params}
          preview={@preview}
          swedish_toggle?={swedish_toggle?(@order)}
        />
        <.record_payment_form
          :if={@mode == :settle and @order.to_collect?}
          id="order-balance"
          record={@order}
          locale={@locale}
          params={@payment_params}
          receipt_email?={!!@order.customer_email}
          preview={@preview}
          swedish_toggle?={swedish_toggle?(@order)}
        />
        <p :if={nothing_to_settle?(@order, @mode)} class="text-base-content/75 text-sm">
          {~t"Nothing left to settle on this order."}
        </p>
      </.drawer_body>
    </.admin_drawer>
    """
  end

  def settlement_title(_order, :refund), do: ~t"Refund"
  def settlement_title(_order, :settle), do: ~t"Record payment"

  def nothing_to_settle?(order, :refund), do: not order.refundable?
  def nothing_to_settle?(order, :settle), do: not order.to_collect?

  attr :form, :any, default: nil
  attr :error, :string, default: nil
  attr :order, Order, required: true
  attr :uploads, :map, required: true
  attr :preview, Swoosh.Email, default: nil

  def confirm_fulfillment(assigns) do
    ~H"""
    <.admin_drawer id="confirm-fulfillment" title={~t"Confirm fulfillment"} on_close={JS.push("cancel_fulfillment")}>
      <.form
        :if={@form}
        for={@form}
        id="confirm-fulfillment-form"
        phx-change="validate_fulfillment"
        phx-submit="mark_fulfilled"
        class="flex min-h-0 flex-1 flex-col"
      >
        <.drawer_body>
          <p :if={@error} role="alert" class="text-error text-sm">{@error}</p>
          <.input
            :let={option}
            :if={@order.fulfillment_method == :delivery}
            field={@form[:customer_home]}
            type="radio-card"
            label={~t"Was the customer home?"}
            options={[%{name: ~t"Yes", value: "true"}, %{name: ~t"No", value: "false"}]}
          >
            {option.name}
          </.input>
          <div :if={@form[:customer_home].value == "false"} class="space-y-4">
            <.photo_input field={@form[:photo]} uploads={@uploads} label={~t"Photo of where you left the order"} />
          </div>
          <.customer_email
            :if={@order.fulfillment_method == :delivery and @order.customer_email}
            id="fulfillment-email"
            send={@form[:email_customer]}
            label={~t"Email delivery confirmation"}
            message={@form[:message]}
            to={@order.customer_email}
            preview={@preview}
            in_swedish={swedish_toggle?(@order) && @form[:in_swedish]}
          />
          <p :if={@order.fulfillment_method == :pickup} class="text-base-content/75 text-sm">
            {~t"The customer collects it in person, so no confirmation is emailed."}
          </p>
          <div
            :if={@order.fulfillment_method == :delivery and !@order.customer_email}
            class="text-base-content/75 space-y-2 text-sm"
          >
            <p>{~t"This order has no email address, so no confirmation will be emailed."}</p>
            <.link navigate={~p"/admin/orders/#{@order.id}/edit"} class="link link-primary">
              {~t"Edit customer details"}
            </.link>
          </div>
          <input
            :if={@order.fulfillment_method == :pickup or !@order.customer_email}
            type="hidden"
            name="fulfillment[email_customer]"
            value="false"
          />
          <p :if={@order.unpaid?} class="text-warning-content text-sm font-semibold">
            {~t"This order is still unpaid."}
          </p>
        </.drawer_body>
        <.drawer_footer>
          <.button
            type="submit"
            variant="primary"
            disabled={@order.fulfillment_method == :delivery and @form[:customer_home].value not in ["true", "false"]}
          >
            {if @order.fulfillment_method == :delivery, do: ~t"Mark as delivered", else: ~t"Mark as collected"}
          </.button>
          <.button
            type="button"
            phx-click={JS.exec("phx-hide", to: "#confirm-fulfillment") |> JS.push("cancel_fulfillment")}
            variant="ghost"
          >{~t"Cancel"}</.button>
        </.drawer_footer>
      </.form>
    </.admin_drawer>
    """
  end

  attr :queue, :map, required: true
  attr :fulfilled, :boolean, required: true

  def queue_nav(assigns) do
    ~H"""
    <nav
      id="order-queue-nav"
      phx-hook=".ArrowKeyNav"
      aria-label={~t"Orders to fulfil"}
      class="border-base-content/12 bg-base-100 divide-base-content/12 flex h-9 items-stretch divide-x border text-sm pointer-coarse:h-11"
    >
      <.queue_link
        to={@queue.previous}
        icon="hero-chevron-left"
        label={~t"Previous order"}
        arrow_key="ArrowLeft"
        transition="pop"
      />
      <span class="text-base-content/80 flex items-center px-3 tabular-nums">
        <%= if @fulfilled do %>
          {~t"Fulfilled · #{remaining_to_fulfil(@queue)} left"}
        <% else %>
          {~t"#{@queue.position} of #{@queue.total} to fulfil"}
        <% end %>
      </span>
      <.queue_link
        to={@queue.next}
        icon="hero-chevron-right"
        label={~t"Next order"}
        arrow_key="ArrowRight"
        transition="push"
      />
    </nav>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ArrowKeyNav">
      /**
       * Follows the link inside the hook element whose `data-arrow-key` matches the
       * pressed arrow key. Clicking the link keeps LiveView's own navigation.
       */
      export default {
        mounted() {
          this.onKeydown = (e) => {
            if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
            if (
              e.target instanceof HTMLElement &&
              e.target.closest("input, textarea, select, [contenteditable]")
            )
              return;

            const link = this.el.querySelector(`a[data-arrow-key="${e.key}"]`);
            if (!(link instanceof HTMLElement)) return;

            e.preventDefault();
            link.click();
          };

          window.addEventListener("keydown", this.onKeydown);
        },

        destroyed() {
          window.removeEventListener("keydown", this.onKeydown);
        },
      };
    </script>
    """
  end

  attr :to, :any, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :arrow_key, :string, required: true

  attr :transition, :string,
    required: true,
    doc: "Page transition in admin_transitions.js, matching the arrow's direction"

  def queue_link(%{to: nil} = assigns) do
    ~H"""
    <span class="text-base-content/25 flex w-9 items-center justify-center pointer-coarse:w-11" aria-hidden="true">
      <.icon name={@icon} class="h-4 w-4" />
    </span>
    """
  end

  def queue_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/admin/orders/#{@to}"}
      class="text-base-content/80 flex w-9 items-center justify-center transition-colors pointer-coarse:w-11 hover:bg-base-200 hover:text-base-content"
      aria-label={@label}
      aria-keyshortcuts={@arrow_key}
      title={~t"#{@label} (#{arrow_symbol(@arrow_key)})"}
      data-arrow-key={@arrow_key}
      data-transition={@transition}
    >
      <.icon name={@icon} class="h-4 w-4" />
    </.link>
    """
  end

  attr :line_items, :list, required: true

  # What to make, not what it costs: the prices are in the Payment section.
  def readonly_line_items(assigns) do
    ~H"""
    <ul class="divide-base-content/12 divide-y">
      <li :for={line_item <- @line_items} class="flex gap-4 py-4 first:pt-0 last:pb-0">
        <div
          :if={is_nil(line_item.product_image_slug)}
          class="bg-base-200 text-base-content/40 flex h-16 w-16 shrink-0 items-center justify-center"
          aria-hidden="true"
        >
          <.icon name="hero-sparkles" class="h-6 w-6" />
        </div>
        <.image
          :if={line_item.product_image_slug}
          src={line_item.product_image_slug}
          alt={~t"Image of #{line_item.product_name}"}
          width={64}
          height={64}
          sizes="64px"
          class="h-16 w-16 shrink-0 object-cover"
        />
        <div class="min-w-0 flex-1">
          <p class="text-base-content text-base font-medium">
            <span class="tabular-nums">{line_item.quantity} ×</span> {line_item.product_name}
          </p>
          <p :if={line_item.variant_size} class="text-base-content/85 mt-0.5 text-sm">
            {variant_size_label(line_item.variant_size)}
          </p>
        </div>
      </li>
    </ul>
    """
  end

  attr :urls, :map, required: true
  attr :sms_label, :string, required: true
  attr :whatsapp_label, :string, required: true

  def message_links(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-x-4 gap-y-1.5">
      <a href={@urls.sms} class="link link-primary touch-target inline-flex items-center gap-1.5">
        <.icon name="hero-chat-bubble-left-ellipsis" class="h-3.5 w-3.5 shrink-0" />
        {@sms_label}
      </a>
      <a
        href={@urls.whatsapp}
        target="_blank"
        rel="noopener"
        class="link link-primary touch-target inline-flex items-center gap-1.5"
      >
        <.icon name="hero-chat-bubble-oval-left" class="h-3.5 w-3.5 shrink-0" />
        {@whatsapp_label}
      </a>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :tone, :atom, required: true, values: [:overdue, :today, :upcoming]

  def relative_date_badge(%{tone: :upcoming} = assigns) do
    ~H"""
    <span class="text-base-content/75 block text-sm font-normal">{@label}</span>
    """
  end

  def relative_date_badge(assigns) do
    ~H"""
    <.badge tone={relative_date_badge_tone(@tone)} class="ml-1.5 align-middle">{@label}</.badge>
    """
  end

  attr :position, :any, required: true
  attr :token, :string, default: nil
  attr :address, :string, default: nil
  attr :distance_km, :any, default: nil

  def delivery_location(assigns) do
    assigns = assign(assigns, :directions, directions_url(assigns.position, assigns.address))

    ~H"""
    <div :if={@directions} id="order-directions" class="border-base-content/12 mt-5 border-t pt-5">
      <div class="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
        <.summary_fact label={~t"Deliver to"}>
          {@address}
          <span :if={@distance_km} class="text-base-content/75 block text-sm font-normal tabular-nums">
            {@distance_km} km
          </span>
        </.summary_fact>
        <a
          href={@directions}
          target="_blank"
          rel="noopener"
          class="link link-primary inline-flex items-center gap-1.5 text-sm"
        >
          {~t"Get directions"}
          <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
        </a>
      </div>
      <a
        :if={@position && present?(@token)}
        href={@directions}
        target="_blank"
        rel="noopener"
        class="mt-3 block overflow-hidden"
        aria-label={~t"Open directions in Google Maps"}
      >
        <img
          src={mapbox_static_url(@position, @token)}
          alt={@address || ~t"Delivery location map"}
          loading="lazy"
          class="block h-48 w-full object-cover"
        />
      </a>
    </div>
    """
  end

  attr :payment, :map, required: true
  attr :locale, :string, required: true

  # Shown as subtracted from the total, so the balance below reads as the sum.
  def payment_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4 py-0.5">
      <dt class="text-base-content/75">
        {payment_label(@payment)} ·
        <time datetime={DateTime.to_iso8601(@payment.paid_at)} title={Format.datetime(@payment.paid_at, @locale)}>
          {@payment.paid_at
          |> DateTime.shift_zone!(Edenflowers.ShopTime.timezone())
          |> DateTime.to_date()
          |> Format.day_month(@locale)}
        </time>
        <a
          :if={@payment.payment_intent_id}
          href={StripeAPI.dashboard_payment_url(@payment.payment_intent_id)}
          target="_blank"
          rel="noopener"
          class="text-base-content/60 touch-target -my-3 -ml-1 inline-flex p-2 align-middle hover:text-base-content"
          aria-label={~t"View #{amount = Format.currency(@payment.amount, @locale)} payment in Stripe"}
        >
          <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
        </a>
        <.button
          :if={@payment.undoable?}
          type="button"
          phx-click="undo_payment"
          phx-value-id={@payment.id}
          data-confirm={undo_confirmation(@payment, @locale)}
          size="sm"
          class="ml-1"
        >
          {~t"Undo"}
        </.button>
        <span :if={@payment.note} class="text-base-content/75 block">{@payment.note}</span>
      </dt>
      <dd class="text-base-content/90 tabular-nums">
        {Format.currency(negate(@payment.amount), @locale)}
      </dd>
    </div>
    """
  end

  attr :order, :map, required: true
  attr :locale, :string, required: true

  # Reminding comes first: it's how most custom orders get paid.
  def payment_link_buttons(assigns) do
    ~H"""
    <.button
      :if={@order.payment_reminder_sendable?}
      type="button"
      phx-click="open_email"
      phx-value-kind="payment_reminder"
      variant="primary"
      size="sm"
    >
      <.icon name="hero-envelope" class="h-4 w-4" />
      {~t"Send payment reminder"}
    </.button>
    <.button :if={!@order.payment_link_open?} type="button" phx-click="open_payment_link" variant="secondary" size="sm">
      {~t"Get payment link"}
    </.button>
    """
  end

  attr :order, :map, required: true
  attr :payment_message_urls, :map, default: nil

  def payment_link(assigns) do
    ~H"""
    <div id="order-payment-link" class="mt-4">
      <label for="payment-link-url" class="eyebrow text-base-content/75 mb-1.5 block">
        {~t"Payment link"}
      </label>
      <div class="flex gap-2">
        <input
          id="payment-link-url"
          type="text"
          readonly
          value={EdenflowersWeb.PaymentLink.url_for(@order)}
          class="input input-sm font-mono min-w-0 flex-1 text-xs"
        />
        <.copy_button id="copy-payment-link" target="#payment-link-url" label={~t"Copy payment link"} />
      </div>
      <div :if={@payment_message_urls} class="mt-2.5 text-sm">
        <.message_links
          urls={@payment_message_urls}
          sms_label={~t"Text payment link"}
          whatsapp_label={~t"WhatsApp payment link"}
        />
      </div>
    </div>
    """
  end

  attr :order, :map, required: true
  attr :payments, :list, required: true
  attr :locale, :string, required: true

  # Always there, so Jennie finds it in the same place on every order. An item
  # that doesn't apply yet says why; one that never could, like fetching Stripe
  # refunds for an order Stripe never charged, is left out.
  def order_menu(assigns) do
    assigns =
      assigns
      |> assign(:paid?, assigns.order.receipt_available?)
      |> assign(:email_details_unavailable, email_details_unavailable(assigns.order))
      |> assign(:no_email, no_email(assigns.order))
      |> assign(:receipt_unavailable, receipt_unavailable(assigns.order))
      |> assign(:confirmation_unavailable, confirmation_unavailable(assigns.order))
      |> assign(:paid_through_stripe?, paid_through_stripe?(assigns.payments))
      |> assign(:cancel_unavailable, cancel_unavailable(assigns.order))

    ~H"""
    <.actions_menu id="order-actions" class="w-56">
      <%!-- One email at a time: the details carry how to pay, so once paid the receipt replaces them. --%>
      <%= if @paid? do %>
        <.actions_menu_button
          :if={!@no_email}
          menu="order-actions"
          phx-click="open_email"
          phx-value-kind="receipt"
        >
          {if @order.receipt_emailed_at, do: ~t"Resend receipt", else: ~t"Email receipt"}
        </.actions_menu_button>
        <.unavailable_menu_item :if={@no_email} reason={@no_email}>
          {~t"Email receipt"}
        </.unavailable_menu_item>
      <% else %>
        <.actions_menu_button
          :if={!@email_details_unavailable}
          menu="order-actions"
          phx-click="open_email"
          phx-value-kind="order_details"
        >
          {if @order.order_details_emailed_at, do: ~t"Resend order details", else: ~t"Email order details"}
        </.actions_menu_button>
        <.unavailable_menu_item :if={@email_details_unavailable} reason={@email_details_unavailable}>
          {~t"Email order details"}
        </.unavailable_menu_item>
      <% end %>

      <.actions_menu_button
        :if={@order.payment_reminder_sendable?}
        menu="order-actions"
        phx-click="open_email"
        phx-value-kind="payment_reminder"
      >
        {~t"Send payment reminder"}
      </.actions_menu_button>

      <%!-- A cancelled order is never fulfilled and a collected one was handed over, so neither has anything to confirm. --%>
      <%= if @order.fulfillment_confirmation_applicable? do %>
        <.actions_menu_button
          :if={!@confirmation_unavailable}
          menu="order-actions"
          phx-click="open_email"
          phx-value-kind="fulfillment"
        >
          {if @order.fulfillment_emailed_at, do: ~t"Resend confirmation", else: ~t"Email confirmation"}
        </.actions_menu_button>
        <.unavailable_menu_item :if={@confirmation_unavailable} reason={@confirmation_unavailable}>
          {~t"Email confirmation"}
        </.unavailable_menu_item>
      <% end %>

      <li :if={!@receipt_unavailable}>
        <.link href={~p"/order/#{@order.id}/receipt"} target="_blank" rel="noopener">
          {~t"View receipt"}
          <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
        </.link>
      </li>
      <.unavailable_menu_item :if={@receipt_unavailable} reason={@receipt_unavailable}>
        {~t"View receipt"}
      </.unavailable_menu_item>

      <.actions_menu_button
        :if={@order.refundable?}
        menu="order-actions"
        phx-click="open_settlement"
        phx-value-mode="refund"
      >
        {~t"Refund"}
      </.actions_menu_button>

      <%!-- Refunds arrive by webhook; this catches one that never did. --%>
      <.actions_menu_button :if={@paid_through_stripe?} menu="order-actions" phx-click="fetch_stripe_refunds">
        {~t"Fetch refunds from Stripe"}
      </.actions_menu_button>

      <.actions_menu_button :if={!@cancel_unavailable} menu="order-actions" phx-click="open_cancel" class="text-error">
        {~t"Cancel order"}
      </.actions_menu_button>
      <.unavailable_menu_item :if={@cancel_unavailable} reason={@cancel_unavailable}>
        {~t"Cancel order"}
      </.unavailable_menu_item>

      <.actions_menu_button
        :if={@order.deletable?}
        menu="order-actions"
        phx-click="delete_order"
        data-confirm={~t"Delete this order for good? Nothing about it is kept."}
        class="text-error"
      >
        {~t"Delete order"}
      </.actions_menu_button>
    </.actions_menu>
    """
  end

  attr :reason, :string, required: true
  slot :inner_block, required: true

  # The reason is written out rather than put in a tooltip, which a touch screen never shows.
  def unavailable_menu_item(assigns) do
    ~H"""
    <li class="menu-disabled">
      <span aria-disabled="true" class="flex flex-col items-start gap-0.5">
        {render_slot(@inner_block)}
        <span class="text-xs">{@reason}</span>
      </span>
    </li>
    """
  end

  def email_details_unavailable(%{details_emailable?: true}), do: nil
  def email_details_unavailable(%{cancelled?: true}), do: ~t"The order is cancelled"
  def email_details_unavailable(order), do: no_email(order)

  def confirmation_unavailable(%{fulfillment_confirmation_sendable?: true}), do: nil
  def confirmation_unavailable(%{customer_email: nil} = order), do: no_email(order)
  def confirmation_unavailable(_order), do: ~t"Not fulfilled yet"

  def receipt_unavailable(%{receipt_available?: true}), do: nil
  def receipt_unavailable(%{payment_status: :refunded}), do: ~t"The order was refunded"
  def receipt_unavailable(_order), do: ~t"Not paid"

  def line_label(%{variant_size: nil} = line_item), do: "#{line_item.quantity} × #{line_item.product_name}"

  def line_label(line_item),
    do: "#{line_item.quantity} × #{line_item.product_name}, #{variant_size_label(line_item.variant_size)}"

  def payment_label(%{reverses_payment_id: reversed, method: method}) when is_binary(reversed),
    do: ~t"Undone · #{how = OrderLog.payment_method_label(method)}"

  def payment_label(%{amount: amount, method: method}) do
    if Decimal.negative?(amount),
      do: ~t"Refund · #{how = OrderLog.payment_method_label(method)}",
      else: OrderLog.payment_method_label(method)
  end

  def paid_through_stripe?(payments), do: Enum.any?(payments, & &1.payment_intent_id)

  def swedish_toggle?(order), do: order.locale != "sv-FI"

  def no_email(%{customer_email: nil}), do: ~t"No email address"
  def no_email(_order), do: nil

  def cancel_unavailable(%{cancellable?: true}), do: nil
  def cancel_unavailable(%{fulfillment_status: :fulfilled}), do: ~t"Already fulfilled"
  def cancel_unavailable(%{fulfillment_status: :cancelled}), do: ~t"Already cancelled"

  # The queue was counted at mount with this order still in it.
  def remaining_to_fulfil(queue), do: queue.total - 1

  def arrow_symbol("ArrowLeft"), do: "←"
  def arrow_symbol("ArrowRight"), do: "→"

  # The phone number is the recipient's only on gift deliveries; the buyer collects pickups.
  def customer_phone?(order), do: !order.gift or order.fulfillment_method == :pickup

  def positive?(nil), do: false
  def positive?(value), do: Decimal.compare(value, 0) == :gt

  def negate(nil), do: nil
  def negate(value), do: Decimal.mult(value, -1)

  def discount_label(%{promotion_code: code}) when is_binary(code) and code != "", do: ~t"Discount (#{code})"
  def discount_label(%{promotion_name: name}) when is_binary(name) and name != "", do: ~t"Discount (#{name})"
  def discount_label(_order), do: ~t"Discount"

  # A fulfilled order is historical, so we skip relative framing there.
  def fulfillment_relative(date, locale, status) when not is_nil(date) and status != :fulfilled do
    today = Edenflowers.ShopTime.today()

    if Date.diff(date, today) == 0,
      do: ~t"Today",
      else: Localize.DateTime.Relative.to_string!(date, relative_to: today, locale: locale) |> upcase_first()
  end

  def fulfillment_relative(_date, _locale, _status), do: nil

  defp upcase_first(string) do
    {first, rest} = String.split_at(string, 1)
    String.upcase(first) <> rest
  end

  def date_tone(date) do
    case Date.compare(date, Edenflowers.ShopTime.today()) do
      :lt -> :overdue
      :eq -> :today
      :gt -> :upcoming
    end
  end

  def relative_date_badge_tone(:overdue), do: :error
  def relative_date_badge_tone(:today), do: :success

  # `position` is stored as a `"lat,lng"` string by HERE geocoding.
  def parse_position(nil), do: nil

  def parse_position(position) do
    case String.split(position, ",") do
      [lat, lng] -> {String.trim(lat), String.trim(lng)}
      _ -> nil
    end
  end

  # Mapbox Static Images API expects `lon,lat` ordering.
  def mapbox_static_url({lat, lng}, token) do
    marker = "pin-s+e8542b(#{lng},#{lat})"
    center = "#{lng},#{lat},14"

    "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/" <>
      "#{marker}/#{center}/1000x280@2x" <>
      "?access_token=#{token}&logo=false&attribution=false"
  end

  # Falls back to the typed address when an order hasn't been geocoded yet.
  def directions_url({lat, lng}, _address), do: maps_dir_url("#{lat},#{lng}")

  def directions_url(nil, address) when is_binary(address) and address != "",
    do: maps_dir_url(address)

  def directions_url(_position, _address), do: nil

  def maps_dir_url(destination) do
    "https://www.google.com/maps/dir/?api=1" <>
      "&origin=#{URI.encode_www_form(Edenflowers.Fulfillment.shop_address())}" <>
      "&destination=#{URI.encode_www_form(destination)}" <>
      "&travelmode=driving"
  end
end

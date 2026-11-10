defmodule EdenflowersWeb.Admin.OrderDetailComponents do
  @moduledoc """
  The order page's drawers, queue nav and menus, with the view helpers they need.
  """

  use EdenflowersWeb, {:html, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.Drawers
  import EdenflowersWeb.Admin.PhotoUpload, only: [photo_input: 1]

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.GiftVoucher
  alias EdenflowersWeb.Admin.OrderLog

  attr :order, Order, required: true
  attr :voucher_form, Phoenix.HTML.Form, default: nil, doc: "on the voucher's `change_last_day`, while it can change"
  attr :locale, :string, required: true

  @doc """
  What a Gift voucher sale sold, in place of the job a flower order shows: everything Jennie copies onto a
  ready-printed card when the buyer collects one.
  """
  def gift_voucher_sold(assigns) do
    ~H"""
    <.widget id="order-gift-voucher" title={~t"Gift voucher"}>
      <p :if={@order.voucher_card_to_hand_over?} class="text-base-content/75 mb-5 text-sm">
        {~t"The buyer collects a gift card at the shop. Write these on one of your cards, then mark it collected."}
      </p>
      <div class="grid grid-cols-1 gap-x-8 gap-y-5 sm:grid-cols-2">
        <.summary_fact label={~t"For"}>{@order.recipient_name || "—"}</.summary_fact>
        <.summary_fact label={~t"Amount"}>
          <span class="tabular-nums">{Format.currency(@order.gift_voucher_line.unit_price, @locale)}</span>
        </.summary_fact>
        <.summary_fact :if={@order.gift_voucher_line.gift_voucher} label={~t"Code"}>
          <span id="order-gift-voucher-code" class="tabular-nums tracking-wider">
            {GiftVoucher.format_code(@order.gift_voucher_line.gift_voucher.code)}
          </span>
        </.summary_fact>
        <.summary_fact :if={@order.gift_voucher_line.gift_voucher} label={~t"Valid until"}>
          <.gift_voucher_last_day
            voucher={@order.gift_voucher_line.gift_voucher}
            form={@voucher_form}
            locale={@locale}
          />
        </.summary_fact>
      </div>
      <blockquote
        :if={present?(@order.card_message)}
        phx-no-format
        class="text-base-content font-serif mt-5 whitespace-pre-wrap break-words text-xl italic leading-relaxed"
      >{@order.card_message}</blockquote>
      <.gift_voucher_spending
        :if={@order.gift_voucher_line.gift_voucher && @order.gift_voucher_line.gift_voucher.payments != []}
        voucher={@order.gift_voucher_line.gift_voucher}
        locale={@locale}
      />
    </.widget>
    """
  end

  attr :voucher, GiftVoucher, required: true
  attr :form, Phoenix.HTML.Form, default: nil
  attr :locale, :string, required: true

  # The date, with Change beside it while the voucher can still be given time; the form opens in its place.
  defp gift_voucher_last_day(assigns) do
    ~H"""
    <div id="gift-voucher-last-day-view" class="flex flex-wrap items-center gap-x-3 gap-y-1">
      <span class="tabular-nums">{Format.date(@voucher.expires_on, @locale)}</span>
      <.button
        :if={@form}
        id="gift-voucher-last-day-open"
        type="button"
        variant="ghost"
        size="sm"
        class="-my-1"
        aria-label={~t"Change last day"}
        phx-click={
          JS.hide(to: "#gift-voucher-last-day-view")
          |> JS.show(to: "#gift-voucher-last-day")
          |> JS.focus(to: "#gift-voucher-expires-on")
        }
      >
        <.icon name="hero-pencil-square" class="h-4 w-4" /> {~t"Change"}
      </.button>
    </div>
    <.form
      :if={@form}
      for={@form}
      id="gift-voucher-last-day"
      phx-change="validate_voucher_last_day"
      phx-submit="change_voucher_last_day"
      novalidate
      class="hidden"
    >
      <.input
        field={@form[:expires_on]}
        id="gift-voucher-expires-on"
        type="date"
        aria-label={~t"Last day"}
        min={Date.to_iso8601(Date.add(@voucher.expires_on, 1))}
        class="input input-sm w-auto tabular-nums"
      />
      <div class="mt-2 flex gap-2">
        <.button type="submit" variant="primary" size="sm">{~t"Save"}</.button>
        <.button
          type="button"
          variant="ghost"
          size="sm"
          phx-click={
            JS.hide(to: "#gift-voucher-last-day")
            |> JS.show(to: "#gift-voucher-last-day-view")
            |> JS.push("cancel_voucher_last_day")
          }
        >
          {~t"Cancel"}
        </.button>
      </div>
    </.form>
    """
  end

  attr :voucher, GiftVoucher, required: true
  attr :locale, :string, required: true

  # Once it's been spent: a small ledger, read like the Payment card, of what it paid for,
  # what was handed back onto it, and what's left.
  defp gift_voucher_spending(assigns) do
    ~H"""
    <dl id="order-gift-voucher-payments" class="border-base-content/12 mt-6 border-t pt-4 text-sm">
      <div :for={payment <- @voucher.payments} class="flex items-baseline justify-between gap-4 py-0.5">
        <dt class="text-base-content/75 min-w-0">
          <.link navigate={spent_on_path(payment)} class="link link-primary">{spent_on(payment)}</.link>
          ·
          <time datetime={DateTime.to_iso8601(payment.paid_at)} title={Format.datetime(payment.paid_at, @locale)}>
            {payment.paid_at
            |> DateTime.shift_zone!(Edenflowers.ShopTime.timezone())
            |> DateTime.to_date()
            |> Format.day_month(@locale)}
          </time>
        </dt>
        <dd class="text-base-content/90 shrink-0 tabular-nums">
          {Format.currency(negate(payment.amount), @locale)}
        </dd>
      </div>
      <div id="order-gift-voucher-remaining" class="border-base-content/12 mt-1.5 border-t pt-1.5">
        <.money_row strong label={~t"Left"} amount={@voucher.remaining} locale={@locale} />
      </div>
    </dl>
    """
  end

  defp spent_on(%{order: %{} = order}),
    do: ~t"Order #{reference = order.order_reference} · #{name = order.customer_name}"

  defp spent_on(%{course_registration: booking}),
    do: ~t"Course #{reference = booking.reference} · #{name = booking.name}"

  defp spent_on_path(%{order: %{} = order}), do: ~p"/admin/orders/#{order.id}"
  defp spent_on_path(%{course_registration: booking}), do: ~p"/admin/courses/#{booking.course_id}"

  attr :order, Order, required: true
  attr :mode, :atom, required: true, values: [:settle, :refund]
  attr :stale, :boolean, default: false
  attr :payment_form, Phoenix.HTML.Form, default: nil, doc: "nil when there is nothing to collect"
  attr :refund_form, Phoenix.HTML.Form, default: nil, doc: "nil when there is nothing to refund"
  attr :locale, :string, required: true
  attr :preview, Swoosh.Email, default: nil

  def settlement_drawer(assigns) do
    ~H"""
    <.admin_drawer id="settlement-drawer" title={settlement_title(@order, @mode)} stale={@stale}>
      <.drawer_body>
        <div class="space-y-1">
          <p :if={@order.customer_name} class="text-base-content font-semibold">{@order.customer_name}</p>
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
        <.refund_form
          :if={@mode == :refund and @order.refundable?}
          id="order-refund"
          record={@order}
          email={@order.customer_email}
          locale={@locale}
          form={@refund_form}
          preview={@preview}
        />
        <.record_payment_form
          :if={@mode == :settle and @order.to_collect?}
          id="order-balance"
          record={@order}
          locale={@locale}
          form={@payment_form}
          receipt_email?={!!@order.customer_email}
          preview={@preview}
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
  attr :photo_error, :string, default: nil
  attr :stale, :boolean, default: false
  attr :order, Order, required: true
  attr :uploads, :map, required: true
  attr :preview, Swoosh.Email, default: nil

  def confirm_fulfillment(assigns) do
    ~H"""
    <.admin_drawer
      id="confirm-fulfillment"
      title={~t"Confirm fulfillment"}
      stale={@stale}
      on_close={JS.push("cancel_fulfillment")}
    >
      <.form
        :if={@form}
        for={@form}
        id="confirm-fulfillment-form"
        phx-change="validate_fulfillment"
        phx-submit="mark_fulfilled"
        class="flex min-h-0 flex-1 flex-col"
      >
        <.drawer_body>
          <.refusal form={@form} />
          <p :if={@photo_error} role="alert" class="text-error text-sm">{@photo_error}</p>
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
            :if={@order.fulfillment_confirmation_applicable? and @order.customer_email}
            id="fulfillment-email"
            send={@form[:email_customer?]}
            label={~t"Email delivery confirmation"}
            form={@form}
            to={@order.customer_email}
            preview={@preview}
          />
          <p :if={!@order.fulfillment_confirmation_applicable?} class="text-base-content/75 text-sm">
            {~t"The customer collects it in person, so no confirmation is emailed."}
          </p>
          <div
            :if={@order.fulfillment_confirmation_applicable? and !@order.customer_email}
            class="text-base-content/75 space-y-2 text-sm"
          >
            <p>{~t"This order has no email address, so no confirmation will be emailed."}</p>
            <.link navigate={~p"/admin/orders/#{@order.id}/edit"} class="link link-primary">
              {~t"Edit customer details"}
            </.link>
          </div>
          <input
            :if={!@order.fulfillment_confirmation_applicable? or !@order.customer_email}
            type="hidden"
            name="fulfillment[email_customer?]"
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
          {~t"#{@queue.position} of #{@queue.total}"}
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
    doc: "Page transition in page_transitions.js, matching the arrow's direction"

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
          <p class="text-base-content text-base">
            <span class="tabular-nums">{line_item.quantity} ×</span> {line_item.product_name}
          </p>
          <p :if={line_item.variant_size || line_item.bow_colour} class="text-base-content/85 mt-0.5 text-sm">
            {Edenflowers.Format.line_item_choices(line_item)}
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
    <div
      :if={@directions}
      id="order-directions"
      class="border-base-content/12 mt-5 border-t pt-5 last:max-sm:has-[img]:-mb-4"
    >
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
        class="mt-3 block overflow-hidden max-sm:-mx-4"
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
      <label for="payment-link-url" class="text-base-content/75 mb-1.5 block text-sm">
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
  attr :locale, :string, required: true

  def order_menu(assigns) do
    ~H"""
    <.actions_menu :if={@order.admin_menu_actions != []} id="order-actions" class="w-56">
      <.actions_menu_button
        :if={:gift_voucher in @order.admin_menu_actions}
        menu="order-actions"
        phx-click="open_email"
        phx-value-kind="gift_voucher"
      >
        {~t"Resend gift voucher"}
      </.actions_menu_button>
      <.actions_menu_button
        :if={:receipt in @order.admin_menu_actions}
        menu="order-actions"
        phx-click="open_email"
        phx-value-kind="receipt"
      >
        {if @order.receipt_emailed_at, do: ~t"Resend receipt", else: ~t"Email receipt"}
      </.actions_menu_button>
      <.actions_menu_button
        :if={:order_details in @order.admin_menu_actions}
        menu="order-actions"
        phx-click="open_email"
        phx-value-kind="order_details"
      >
        {if @order.order_details_emailed_at, do: ~t"Resend order details", else: ~t"Email order details"}
      </.actions_menu_button>
      <.actions_menu_button
        :if={:payment_reminder in @order.admin_menu_actions}
        menu="order-actions"
        phx-click="open_email"
        phx-value-kind="payment_reminder"
      >
        {~t"Send payment reminder"}
      </.actions_menu_button>
      <.actions_menu_button
        :if={:fulfillment in @order.admin_menu_actions}
        menu="order-actions"
        phx-click="open_email"
        phx-value-kind="fulfillment"
      >
        {if @order.fulfillment_emailed_at, do: ~t"Resend confirmation", else: ~t"Email confirmation"}
      </.actions_menu_button>

      <li :if={:view_receipt in @order.admin_menu_actions}>
        <.link href={~p"/order/#{@order.id}/receipt"} target="_blank" rel="noopener">
          {~t"View receipt"}
          <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
        </.link>
      </li>

      <.actions_menu_button
        :if={:refund in @order.admin_menu_actions}
        menu="order-actions"
        phx-click="open_settlement"
        phx-value-mode="refund"
      >
        {~t"Refund"}
      </.actions_menu_button>

      <%!-- In the menu, behind a confirmation, so a linked card isn't removed by a stray tap. --%>
      <.actions_menu_button
        :if={:unlink_card in @order.admin_menu_actions}
        menu="order-actions"
        phx-click="unlink_card"
        data-confirm={~t"Remove card #{code = @order.pass_it_on_card.code} from this gift?"}
      >
        {~t"Remove Pass it on card"}
      </.actions_menu_button>

      <.actions_menu_button
        :if={:cancel in @order.admin_menu_actions}
        menu="order-actions"
        phx-click="open_cancel"
        class="text-error"
      >
        {~t"Cancel order"}
      </.actions_menu_button>
    </.actions_menu>
    """
  end

  def line_label(line_item) do
    "#{line_item.quantity} × #{Edenflowers.Format.line_item_name(line_item)}"
  end

  def payment_label(%{reverses_payment_id: reversed, method: method}) when is_binary(reversed),
    do: ~t"Undone · #{how = OrderLog.payment_method_label(method)}"

  def payment_label(%{amount: amount, method: method}) do
    if Decimal.negative?(amount),
      do: ~t"Refund · #{how = OrderLog.payment_method_label(method)}",
      else: OrderLog.payment_method_label(method)
  end

  # The queue was counted at mount with this order still in it.
  def remaining_to_fulfil(queue), do: queue.total - 1

  def arrow_symbol("ArrowLeft"), do: "←"
  def arrow_symbol("ArrowRight"), do: "→"

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

  # No origin, so Google Maps starts from the device's current location.
  def maps_dir_url(destination) do
    "https://www.google.com/maps/dir/?api=1" <>
      "&destination=#{URI.encode_www_form(destination)}" <>
      "&travelmode=driving"
  end

  attr :order, Order, required: true
  attr :locale, :string, required: true

  @doc """
  The order's pass-it-on card (or a field to link one), its source gift and
  the orders its own card brought in. Follow each link to continue the chain.
  """
  def pass_it_on_card(assigns) do
    assigns = assign(assigns, :source, assigns.order.promotion && assigns.order.promotion.gift_order)

    ~H"""
    <.widget id="order-pass-it-on" title={~t"Pass it on"}>
      <div class="space-y-5">
        <p
          :if={@order.gift && !@order.pass_it_on_card && !@order.pass_it_on_card_changeable?}
          id="order-card-none"
          class="text-base-content/65 text-sm"
        >
          {~t"No card went with this gift."}
        </p>

        <div :if={@order.pass_it_on_card_changeable? && !@order.pass_it_on_card} class="space-y-4">
          <div
            id="order-card-missing"
            class="bg-warning/15 border-base-content/12 flex gap-2.5 border px-3 py-2.5"
          >
            <.icon name="hero-gift" class="text-warning-content mt-0.5 h-5 w-5 shrink-0" />
            <div class="text-sm">
              <p class="text-warning-content font-semibold">{~t"No card linked to this gift"}</p>
              <p class="text-base-content mt-0.5">{~t"Type the code printed under the card's QR code."}</p>
            </div>
          </div>
          <.form for={%{}} id="link-card-form" phx-submit="link_card" class="flex items-end gap-2">
            <.input
              name="code"
              value=""
              label={~t"Code on the card"}
              autocomplete="off"
              autocapitalize="characters"
              required
              class="input w-32 uppercase tracking-wider"
            />
            <.button type="submit" variant="secondary">{~t"Link card"}</.button>
          </.form>
        </div>

        <section
          :if={match?(%{kind: :pass_it_on}, @order.promotion)}
          id="order-card-source"
          aria-labelledby="order-card-source-title"
          class="space-y-2"
        >
          <h3 id="order-card-source-title" class="text-base-content flex items-center gap-2 text-sm font-semibold">
            <.icon name="hero-arrow-left" class="h-4 w-4" />
            <% gettext_comment("The gift order this order's discount card came from, not a product or payment source.") %>
            {~t"Source gift"}
          </h3>
          <.card_code code={@order.promotion.code} />
          <.related_order :if={@source && @source.committed?} order={@source} locale={@locale} />
          <p :if={!@source || !@source.committed?} class="text-base-content/65 text-sm">
            {~t"Source gift not linked"}
          </p>
        </section>

        <section :if={@order.pass_it_on_card} id="order-card-outgoing" class="space-y-3">
          <div class="flex flex-wrap items-center gap-2">
            <.card_code code={@order.pass_it_on_card.code} />
            <.card_status_badge card={@order.pass_it_on_card} locale={@locale} />
          </div>
          <div :if={@order.pass_it_on_card.placed_orders != []} class="space-y-2">
            <h3 class="text-base-content flex items-center gap-2 text-sm font-semibold">
              <.icon name="hero-arrow-right" class="h-4 w-4" />
              <% gettext_comment("Orders placed using the pass-it-on card sent with this gift.") %>
              {~t"Orders brought in"}
            </h3>
            <ul class="space-y-2">
              <li :for={order <- @order.pass_it_on_card.placed_orders} id={"order-card-redemption-#{order.id}"}>
                <.related_order order={order} locale={@locale} />
              </li>
            </ul>
          </div>
        </section>
      </div>
    </.widget>
    """
  end

  attr :code, :any, required: true

  defp card_code(assigns) do
    ~H"""
    <span class="border-base-content/30 text-base-content/80 font-mono border px-2 py-0.5 text-xs tracking-wider">
      <span class="sr-only">{~t"Code on the card"}: </span>
      {@code}
    </span>
    """
  end

  attr :card, :any, required: true
  attr :locale, :string, required: true

  defp card_status_badge(%{card: %{card_status: :used}} = assigns) do
    ~H"""
    <.badge tone={:success}>{~t"Used"}</.badge>
    """
  end

  defp card_status_badge(%{card: %{card_status: :opened}} = assigns) do
    ~H"""
    <.badge tone={:attention}>
      {~t"Opened · valid until #{date = Format.date(@card.expiration_date, @locale)}"}
    </.badge>
    """
  end

  defp card_status_badge(%{card: %{card_status: :expired}} = assigns) do
    ~H"""
    <.badge tone={:warning}>{~t"Expired"}</.badge>
    """
  end

  defp card_status_badge(assigns) do
    ~H"""
    <.badge tone={:neutral}>{~t"Not opened yet"}</.badge>
    """
  end

  attr :order, Order, required: true
  attr :locale, :string, required: true

  defp related_order(assigns) do
    ~H"""
    <div>
      <.link navigate={~p"/admin/orders/#{@order.id}"} class="group min-h-11 flex items-center gap-3 text-sm">
        <span class="min-w-0 flex-1">
          <span class="text-base-content block truncate font-semibold group-hover:underline">
            {@order.customer_name || ~t"Unnamed customer"}
          </span>
          <span :if={@order.gift && @order.recipient_name} class="text-base-content/65 block truncate">
            {~t"For #{name = @order.recipient_name}"}
          </span>
        </span>
        <span class="text-base-content/65 shrink-0 tabular-nums">
          {@order.order_reference}<span :if={@order.fulfillment_date}> · {Format.day_month(@order.fulfillment_date, @locale)}</span>
        </span>
      </.link>
      <span :if={@order.fulfillment_status == :cancelled}>
        <.fulfillment_status_badge status={:cancelled} />
      </span>
    </div>
    """
  end
end

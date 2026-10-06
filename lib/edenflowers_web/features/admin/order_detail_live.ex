defmodule EdenflowersWeb.Admin.OrderDetailLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Order.PaymentMethod
  alias Edenflowers.PhoneNumber
  alias Edenflowers.External.StripeAPI
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Orders.get_order_for_admin(id, actor: socket.assigns.current_user) do
      {:ok, %Order{} = order} ->
        {:ok,
         socket
         |> assign(:page_title, ~t"Order #{order.order_reference}")
         |> assign(:locale, Localize.get_locale())
         |> assign(:mapbox_token, Application.get_env(:edenflowers, :mapbox_token))
         |> assign_order(order)
         |> assign(:queue, queue_position(order, socket.assigns.current_user))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Order not found.")
         |> push_navigate(to: EdenflowersWeb.Admin.OrdersLive.default_path())}
    end
  end

  defp assign_order(socket, order) do
    socket
    |> assign(:order, order)
    |> assign(:pickup_message_urls, pickup_message_urls(order))
    |> assign(:note_form, to_form(%{"florist_note" => order.florist_note}, as: :note))
    |> assign(:in_person_form, in_person_form(order))
  end

  defp in_person_form(order) do
    to_form(%{"payment_method" => "zettle", "amount_paid" => Decimal.to_string(order.grand_total, :normal)},
      as: :in_person
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="wide">
        <.admin_page_header
          title={@order.customer_name || @order.order_reference}
          back={EdenflowersWeb.Admin.OrdersLive.default_path()}
          back_label={~t"Orders"}
        >
          <:nav :if={@queue}>
            <.queue_nav queue={@queue} fulfilled={@order.fulfillment_status == :fulfilled} />
          </:nav>
          <:subtitle>
            <span class="inline-flex flex-wrap items-center gap-x-2 gap-y-1">
              <span :if={@order.origin == :custom} class="badge badge-soft badge-sm badge-neutral whitespace-nowrap">
                {~t"Custom order"}
              </span>
              <.gift_badge :if={@order.gift} order={@order} />
              <span class="tabular-nums">{@order.order_reference}</span>
              <span :if={@order.ordered_at} aria-hidden="true">·</span>
              <span :if={@order.ordered_at}>{Format.datetime(@order.ordered_at, @locale)}</span>
            </span>
          </:subtitle>
          <:actions>
            <div :if={@order.fulfillment_status == :pending} class="flex items-center gap-2">
              <.button navigate={~p"/admin/orders/#{@order.id}/edit"} variant="secondary" size="sm">
                <.icon name="hero-pencil-square" class="h-4 w-4" /> {~t"Edit"}
              </.button>
              <.button
                type="button"
                phx-click="cancel_order"
                data-confirm={cancel_confirmation(@order)}
                variant="ghost"
                size="sm"
                class="text-error"
              >
                {~t"Cancel order"}
              </.button>
            </div>
            <div class="flex items-center gap-4">
              <div class="flex flex-col items-start gap-1">
                <span class="eyebrow text-base-content/65">{~t"Payment"}</span>
                <.payment_status_badge status={@order.payment_status} />
              </div>
              <div class="flex flex-col items-start gap-1">
                <span class="eyebrow text-base-content/65">{~t"Fulfillment"}</span>
                <.fulfillment_status_badge status={@order.fulfillment_status} />
              </div>
            </div>
          </:actions>
        </.admin_page_header>

        <section
          id="order-fulfillment-summary"
          class="bg-base-100 border-base-content/12 mb-6 border p-4 sm:p-5"
        >
          <div class="mb-5 flex items-center justify-between gap-4">
            <h2 class="text-base-content text-base font-semibold">{~t"Fulfillment"}</h2>
            <.button
              :if={@order.fulfillment_status == :pending}
              type="button"
              phx-click="mark_fulfilled"
              data-confirm={
                if @order.unpaid?,
                  do: ~t"This order is still unpaid. Mark it as fulfilled anyway?",
                  else: ~t"Mark this order as fulfilled?"
              }
              variant="primary"
              size="sm"
              class="shrink-0"
            >
              {~t"Mark as fulfilled"}
            </.button>
          </div>

          <div class="grid grid-cols-1 gap-x-8 gap-y-5 sm:grid-cols-3">
            <.summary_fact label={~t"Date"}>
              {Format.weekday_day_month(@order.fulfillment_date, @locale)}
              <.relative_date_badge
                :if={fulfillment_relative(@order.fulfillment_date, @locale, @order.fulfillment_status)}
                label={fulfillment_relative(@order.fulfillment_date, @locale, @order.fulfillment_status)}
                tone={date_tone(@order.fulfillment_date)}
              />
            </.summary_fact>
            <.summary_fact label={~t"Method"}>
              <.fulfillment_method
                method={@order.fulfillment_method}
                label={present?(@order.fulfillment_option_name) && @order.fulfillment_option_name}
                class="whitespace-normal"
              />
            </.summary_fact>
            <.summary_fact
              :if={@order.fulfillment_method == :delivery && present?(@order.delivery_address)}
              label={~t"Deliver to"}
            >
              {@order.delivery_address}
              <span :if={@order.distance_km} class="text-base-content/65 block text-sm font-normal tabular-nums">
                {@order.distance_km} km
              </span>
            </.summary_fact>
          </div>

          <div
            :if={present?(@order.delivery_instructions)}
            class="bg-warning/15 border-warning/40 mt-5 flex gap-2.5 border px-3 py-2.5"
          >
            <.icon name="hero-information-circle" class="text-warning-content mt-0.5 h-5 w-5 shrink-0" />
            <div>
              <p class="text-warning-content text-sm font-semibold">{~t"Delivery instructions"}</p>
              <p class="text-base-content mt-0.5 whitespace-pre-wrap break-words">{@order.delivery_instructions}</p>
            </div>
          </div>

          <.delivery_map
            :if={@order.fulfillment_method == :delivery}
            position={parse_position(@order.position)}
            token={@mapbox_token}
            address={@order.delivery_address}
          />
        </section>

        <div class="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <div class="space-y-6">
            <.detail_section id="order-florist-note" title={~t"Florist note"}>
              <.form for={@note_form} id="florist-note-form" phx-submit="save_florist_note" class="space-y-3">
                <.input
                  field={@note_form[:florist_note]}
                  type="textarea"
                  rows="3"
                  placeholder={~t"Only you see this: what was agreed, timings, anything to remember."}
                />
                <.button type="submit" variant="secondary" size="sm">{~t"Save note"}</.button>
              </.form>
            </.detail_section>

            <.detail_section id="order-items" title={~t"To make"}>
              <.readonly_line_items line_items={@order.line_items} locale={@locale} />
            </.detail_section>
            <.detail_section :if={present?(@order.card_message)} id="order-card" title={~t"Card to write"}>
              <blockquote
                phx-no-format
                class="text-base-content font-serif whitespace-pre-wrap break-words text-xl italic leading-relaxed"
              >{@order.card_message}</blockquote>
            </.detail_section>

            <.detail_section id="order-payment-summary" title={~t"Payment"}>
              <dl class="text-sm">
                <.money_row
                  label={~t"Items subtotal"}
                  amount={@order.items_subtotal}
                  locale={@locale}
                />
                <.money_row
                  :if={positive?(@order.discount)}
                  label={discount_label(@order)}
                  amount={negate(@order.discount)}
                  locale={@locale}
                />
                <.money_row label={~t"Fulfillment fee"} amount={@order.fulfillment_fee} locale={@locale} />
                <.money_row strong label={~t"Total"} amount={@order.grand_total} locale={@locale} />
                <.money_row
                  :if={@order.amount_mismatch?}
                  label={amount_paid_label(@order)}
                  amount={@order.amount_paid}
                  locale={@locale}
                />
                <.money_row muted label={~t"Includes VAT"} amount={@order.vat} locale={@locale} />
              </dl>
              <p :if={@order.payment_status == :paid} id="order-paid-how" class="text-base-content/75 mt-4 text-sm">
                {paid_how(@order, @locale)}
              </p>

              <div :if={@order.payment_link_open?} id="order-payment-link" class="mt-5">
                <p class="eyebrow text-base-content/65 mb-1.5">{~t"Payment link"}</p>
                <div class="flex gap-2">
                  <input
                    id="payment-link-url"
                    type="text"
                    readonly
                    value={EdenflowersWeb.PaymentLink.url_for(@order)}
                    class="input input-sm font-mono min-w-0 flex-1"
                  />
                  <.button
                    type="button"
                    phx-click={JS.dispatch("edenflowers:copy", to: "#payment-link-url")}
                    variant="secondary"
                    size="sm"
                  >
                    {~t"Copy"}
                  </.button>
                </div>
              </div>

              <.form
                :if={@order.unpaid?}
                for={@in_person_form}
                id="in-person-payment-form"
                phx-submit="record_in_person_payment"
                class="border-base-content/12 mt-5 space-y-3 border-t pt-5"
              >
                <p class="text-base-content text-sm font-semibold">{~t"Paid in person"}</p>
                <div class="grid grid-cols-2 gap-3">
                  <.input
                    field={@in_person_form[:payment_method]}
                    type="select"
                    label={~t"How"}
                    options={in_person_method_options()}
                  />
                  <.input
                    field={@in_person_form[:amount_paid]}
                    type="text"
                    inputmode="decimal"
                    label={~t"Amount (€)"}
                    class="input w-full tabular-nums"
                  />
                </div>
                <.button type="submit" variant="primary" size="sm">{~t"Mark as paid"}</.button>
              </.form>

              <div class="mt-5 flex flex-wrap gap-2">
                <.button
                  :if={@order.origin == :custom && @order.unpaid? && !@order.payment_link_open?}
                  type="button"
                  phx-click="open_payment_link"
                  variant="secondary"
                  size="sm"
                >
                  {~t"Create payment link"}
                </.button>
                <.button
                  :if={@order.origin == :custom && @order.customer_email && @order.fulfillment_status != :cancelled}
                  type="button"
                  phx-click="send_order_details"
                  data-confirm={~t"Email the order details to #{email = @order.customer_email}?"}
                  variant="secondary"
                  size="sm"
                >
                  {~t"Email order details"}
                </.button>
                <.button
                  :if={
                    @order.payment_status == :paid && @order.payment_method in PaymentMethod.in_person() &&
                      @order.customer_email
                  }
                  type="button"
                  phx-click="email_receipt"
                  data-confirm={~t"Email the receipt to #{email = @order.customer_email}?"}
                  variant="secondary"
                  size="sm"
                >
                  {~t"Email receipt"}
                </.button>
                <.button
                  :if={@order.payment_status == :paid}
                  href={~p"/order/#{@order.id}/receipt"}
                  target="_blank"
                  rel="noopener"
                  variant="secondary"
                  size="sm"
                >
                  {~t"View receipt"}
                  <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                </.button>
                <.button
                  :if={@order.payment_intent_id}
                  href={StripeAPI.dashboard_payment_url(@order.payment_intent_id)}
                  target="_blank"
                  rel="noopener"
                  variant="secondary"
                  size="sm"
                >
                  {~t"View payment in Stripe"}
                  <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                </.button>
              </div>
            </.detail_section>
          </div>

          <aside class="space-y-6">
            <.detail_section id="order-customer" title={~t"Customer"}>
              <.person_block>
                <:contact :if={@order.customer_email}>
                  <a
                    href={fastmail_search_url(@order.customer_email)}
                    target="_blank"
                    rel="noopener"
                    class="link link-primary inline-flex items-center gap-1.5"
                    title={~t"Search Fastmail for this address"}
                  >
                    <.icon name="hero-envelope" class="h-3.5 w-3.5 shrink-0" />
                    <span class="break-all">{@order.customer_email}</span>
                  </a>
                </:contact>
                <:contact :if={present?(@order.customer_phone_number)}>
                  <.phone_link phone_number={@order.customer_phone_number} />
                </:contact>
                <:contact :if={
                  !present?(@order.customer_phone_number) && customer_phone?(@order) &&
                    present?(@order.recipient_phone_number)
                }>
                  <.phone_link phone_number={@order.recipient_phone_number} />
                </:contact>
                <:contact :if={@pickup_message_urls}>
                  <.ready_for_pickup_links urls={@pickup_message_urls} />
                </:contact>
                <:contact :if={@order.user_id}>
                  <.link
                    id="order-customer-link"
                    navigate={~p"/admin/customers/#{@order.user_id}"}
                    class="link link-primary inline-flex items-center gap-1.5"
                  >
                    <.icon name="hero-user" class="h-3.5 w-3.5 shrink-0" />
                    {~t"View customer's orders"}
                  </.link>
                </:contact>
              </.person_block>
            </.detail_section>

            <.detail_section
              :if={@order.gift && present?(@order.recipient_name)}
              id="order-recipient"
              title={~t"Recipient"}
            >
              <.person_block name={@order.recipient_name}>
                <:contact :if={
                  (present?(@order.customer_phone_number) || !customer_phone?(@order)) &&
                    present?(@order.recipient_phone_number)
                }>
                  <.phone_link phone_number={@order.recipient_phone_number} />
                </:contact>
              </.person_block>
            </.detail_section>
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("mark_fulfilled", _params, socket) do
    case Orders.mark_order_fulfilled(socket.assigns.order, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply,
         socket
         |> assign_order(reload(order, socket))
         |> put_flash(:info, ~t"Order marked as fulfilled.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not mark order as fulfilled.")}
    end
  end

  def handle_event("save_florist_note", %{"note" => %{"florist_note" => note}}, socket) do
    case Orders.update_florist_note(socket.assigns.order, %{florist_note: note}, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:info, ~t"Note saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not save the note.")}
    end
  end

  def handle_event("cancel_order", _params, socket) do
    case Orders.cancel_order(socket.assigns.order, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:info, ~t"Order cancelled.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not cancel the order.")}
    end
  end

  def handle_event("record_in_person_payment", %{"in_person" => params}, socket) do
    attrs = %{payment_method: params["payment_method"], amount_paid: String.replace(params["amount_paid"], ",", ".")}

    case Orders.record_in_person_payment(socket.assigns.order, attrs, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:info, ~t"Payment recorded.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not record the payment. Check the amount.")}
    end
  end

  def handle_event("open_payment_link", _params, socket) do
    case Orders.open_payment_link(socket.assigns.order, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:info, ~t"Payment link created.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not create a payment link.")}
    end
  end

  def handle_event("send_order_details", _params, socket) do
    case Orders.send_order_details_email(socket.assigns.order, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:info, ~t"Order details sent.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not send the email. Try again in a moment.")}
    end
  end

  def handle_event("email_receipt", _params, socket) do
    case Orders.email_receipt(socket.assigns.order, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:info, ~t"Receipt sent.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not send the receipt. Try again in a moment.")}
    end
  end

  defp reload(order, socket), do: Orders.get_order_for_admin!(order.id, actor: socket.assigns.current_user)

  defp cancel_confirmation(%{payment_status: :paid}),
    do: ~t"Cancel this order? It is paid, so refund the customer in Stripe or by hand. This can't be undone."

  defp cancel_confirmation(_order), do: ~t"Cancel this order? This can't be undone."

  defp in_person_method_options do
    Enum.map(PaymentMethod.in_person(), &{payment_method_label(&1), &1})
  end

  defp payment_method_label(:stripe), do: ~t"Online (Stripe)"
  defp payment_method_label(:zettle), do: ~t"Card (Zettle)"
  defp payment_method_label(:mobilepay), do: ~t"MobilePay"
  defp payment_method_label(:cash), do: ~t"Cash"
  defp payment_method_label(_method), do: ~t"Unknown"

  defp paid_how(%{payment_method: method, paid_at: %DateTime{} = paid_at}, locale),
    do: ~t"Paid #{time = Format.datetime(paid_at, locale)} · #{how = payment_method_label(method)}"

  defp paid_how(%{payment_method: method}, _locale), do: ~t"Paid · #{how = payment_method_label(method)}"

  defp amount_paid_label(%{payment_method: :stripe}), do: ~t"Charged by Stripe (mismatch)"
  defp amount_paid_label(_order), do: ~t"Taken in person (differs)"

  attr :queue, :map, required: true
  attr :fulfilled, :boolean, required: true

  defp queue_nav(assigns) do
    ~H"""
    <nav
      id="order-queue-nav"
      phx-hook="ArrowKeyNav"
      aria-label={~t"Orders to fulfil"}
      class="border-base-content/12 bg-base-100 divide-base-content/12 flex h-9 items-stretch divide-x border text-sm"
    >
      <.queue_link to={@queue.previous} icon="hero-chevron-left" label={~t"Previous order"} arrow_key="ArrowLeft" />
      <span class="text-base-content/80 flex items-center px-3 tabular-nums">
        <%= if @fulfilled do %>
          {~t"Fulfilled · #{remaining_to_fulfil(@queue)} left"}
        <% else %>
          {~t"#{@queue.position} of #{@queue.total} to fulfil"}
        <% end %>
      </span>
      <.queue_link to={@queue.next} icon="hero-chevron-right" label={~t"Next order"} arrow_key="ArrowRight" />
    </nav>
    """
  end

  attr :to, :any, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :arrow_key, :string, required: true

  defp queue_link(%{to: nil} = assigns) do
    ~H"""
    <span class="text-base-content/25 flex w-9 items-center justify-center" aria-hidden="true">
      <.icon name={@icon} class="h-4 w-4" />
    </span>
    """
  end

  defp queue_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/admin/orders/#{@to}"}
      class="text-base-content/80 flex w-9 items-center justify-center transition-colors hover:bg-base-200 hover:text-base-content"
      aria-label={@label}
      aria-keyshortcuts={@arrow_key}
      title={~t"#{@label} (#{arrow_symbol(@arrow_key)})"}
      data-arrow-key={@arrow_key}
    >
      <.icon name={@icon} class="h-4 w-4" />
    </.link>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp detail_section(assigns) do
    ~H"""
    <section id={@id} class="bg-base-100 border-base-content/12 border p-4 sm:p-5">
      <h2 class="text-base-content mb-4 text-base font-semibold">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :line_items, :list, required: true
  attr :locale, :string, required: true

  defp readonly_line_items(assigns) do
    ~H"""
    <ul class="divide-base-content/8 divide-y">
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
          <div class="flex gap-3">
            <div class="min-w-0 flex-1">
              <p class="text-base-content text-base font-medium">
                <span class="tabular-nums">{line_item.quantity} ×</span> {line_item.product_name}
              </p>
              <p :if={line_item.variant_size} class="text-base-content/85 mt-0.5 text-sm">
                {variant_size_label(line_item.variant_size)}
              </p>
            </div>
            <p class="text-base-content/65 text-sm tabular-nums">{Format.currency(line_item.subtotal, @locale)}</p>
          </div>
        </div>
      </li>
    </ul>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp summary_fact(assigns) do
    ~H"""
    <div>
      <p class="eyebrow text-base-content/65 mb-1.5">{@label}</p>
      <div class="text-base-content text-base font-medium leading-relaxed">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :name, :string, default: nil
  slot :contact

  defp person_block(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <p :if={@name} class="text-base-content text-base font-medium">{@name}</p>
      <div :for={contact <- @contact} class="text-sm">{render_slot(contact)}</div>
    </div>
    """
  end

  attr :phone_number, :string, required: true

  defp phone_link(assigns) do
    ~H"""
    <a
      href={"tel:#{@phone_number}"}
      class="link link-primary inline-flex items-center gap-1.5"
    >
      <.icon name="hero-phone" class="h-3.5 w-3.5 shrink-0" />
      {@phone_number}
    </a>
    """
  end

  attr :urls, :map, required: true

  defp ready_for_pickup_links(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-x-4 gap-y-1.5">
      <a href={@urls.sms} class="link link-primary inline-flex items-center gap-1.5">
        <.icon name="hero-chat-bubble-left-ellipsis" class="h-3.5 w-3.5 shrink-0" />
        {~t"Text ready for pickup"}
      </a>
      <a
        href={@urls.whatsapp}
        target="_blank"
        rel="noopener"
        class="link link-primary inline-flex items-center gap-1.5"
      >
        <.icon name="hero-chat-bubble-oval-left" class="h-3.5 w-3.5 shrink-0" />
        {~t"WhatsApp ready for pickup"}
      </a>
    </div>
    """
  end

  attr :order, :map, required: true

  defp gift_badge(assigns) do
    ~H"""
    <span
      class="badge badge-soft badge-sm badge-neutral inline-flex items-center gap-1 whitespace-nowrap"
      title={(present?(@order.recipient_name) && ~t"Gift for #{@order.recipient_name}") || ~t"Gift order"}
    >
      <.icon name="hero-gift" class="h-3.5 w-3.5" />
      <span :if={present?(@order.recipient_name)} class="max-w-[10rem] truncate">{@order.recipient_name}</span>
      <span :if={!present?(@order.recipient_name)}>{~t"Gift"}</span>
    </span>
    """
  end

  attr :label, :string, required: true
  attr :tone, :atom, required: true, values: [:overdue, :today, :upcoming]

  defp relative_date_badge(%{tone: :upcoming} = assigns) do
    ~H"""
    <span class="text-base-content/65 block text-sm font-normal">{@label}</span>
    """
  end

  defp relative_date_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm ml-1.5 whitespace-nowrap align-middle font-medium", relative_date_badge_class(@tone)]}>
      {@label}
    </span>
    """
  end

  attr :position, :any, required: true
  attr :token, :string, default: nil
  attr :address, :string, default: nil

  defp delivery_map(assigns) do
    assigns = assign(assigns, :directions, directions_url(assigns.position, assigns.address))

    ~H"""
    <div :if={@directions} class="border-base-content/12 mt-6 overflow-hidden border">
      <a
        href={@directions}
        target="_blank"
        rel="noopener"
        class="group block"
        aria-label={~t"Open directions in Google Maps"}
      >
        <img
          :if={@position && present?(@token)}
          src={mapbox_static_url(@position, @token)}
          alt={@address || ~t"Delivery location map"}
          loading="lazy"
          class="block h-44 w-full object-cover"
        />
        <div class="bg-base-100 flex items-center justify-center gap-1.5 px-3 py-2 text-sm transition-colors group-hover:bg-base-200/50">
          <.icon name="hero-map-pin" class="text-base-content/60 h-4 w-4" />
          <span class="link link-primary">{~t"Get directions"}</span>
          <.icon name="hero-arrow-top-right-on-square" class="text-base-content/60 h-3.5 w-3.5" />
        </div>
      </a>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :amount, :any, default: nil
  attr :locale, :string, required: true
  attr :strong, :boolean, default: false
  attr :muted, :boolean, default: false, doc: "for figures already counted in the total, like included VAT"

  defp money_row(assigns) do
    ~H"""
    <div class={["flex items-center justify-between gap-4 py-0.5", @strong && "border-base-content/12 text-base-content mt-1.5 border-t pt-3 text-base font-semibold", @muted && "text-base-content/65"]}>
      <dt class={money_row_tone(@strong, @muted, "text-base-content/75")}>
        {@label}
      </dt>
      <dd class={["tabular-nums", money_row_tone(@strong, @muted, "text-base-content/90")]}>
        {Format.currency(@amount, @locale)}
      </dd>
    </div>
    """
  end

  # Muted rows inherit the row's own muted tone.
  defp money_row_tone(true = _strong, _muted, _default), do: "text-base-content"
  defp money_row_tone(_strong, true = _muted, _default), do: nil
  defp money_row_tone(_strong, _muted, default), do: default

  # Steps through the same queue the orders list opens on. Orders outside it,
  # like fulfilled ones, get no stepping. Computed once at mount so marking this
  # order fulfilled still leaves "next" pointing at the following one.
  defp queue_position(order, actor) do
    ids = Enum.map(Orders.list_orders_to_fulfil!(actor: actor), & &1.id)

    case Enum.find_index(ids, &(&1 == order.id)) do
      nil ->
        nil

      index ->
        %{
          position: index + 1,
          total: length(ids),
          previous: if(index > 0, do: Enum.at(ids, index - 1)),
          next: Enum.at(ids, index + 1)
        }
    end
  end

  # The queue was counted at mount with this order still in it.
  defp remaining_to_fulfil(queue), do: queue.total - 1

  defp arrow_symbol("ArrowLeft"), do: "←"
  defp arrow_symbol("ArrowRight"), do: "→"

  # The phone number is the recipient's only on gift deliveries; the buyer collects pickups.
  defp customer_phone?(order), do: !order.gift or order.fulfillment_method == :pickup

  defp pickup_message_urls(%{fulfillment_method: :pickup, fulfillment_status: :pending} = order) do
    case PhoneNumber.format(order.recipient_phone_number, :e164) do
      {:ok, e164} ->
        body = URI.encode(pickup_message(order), &URI.char_unreserved?/1)

        # iOS reads `&body=`, Android reads `?body=`; `?&body=` satisfies both.
        %{
          sms: "sms:#{e164}?&body=#{body}",
          whatsapp: "https://wa.me/#{String.trim_leading(e164, "+")}?text=#{body}"
        }

      :error ->
        nil
    end
  end

  defp pickup_message_urls(_order), do: nil

  # Written in the customer's language, not the admin's.
  defp pickup_message(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      ~t"Hi #{order.customer_first_name}, your Eden Flowers order #{order.order_reference} is ready for pick up."
    end)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp positive?(nil), do: false
  defp positive?(value), do: Decimal.compare(value, 0) == :gt

  defp negate(nil), do: nil
  defp negate(value), do: Decimal.mult(value, -1)

  defp discount_label(%{promotion_code: code}) when is_binary(code) and code != "", do: ~t"Discount (#{code})"
  defp discount_label(%{promotion_name: name}) when is_binary(name) and name != "", do: ~t"Discount (#{name})"
  defp discount_label(_order), do: ~t"Discount"

  # A fulfilled order is historical, so we skip relative framing there.
  defp fulfillment_relative(date, locale, status) when not is_nil(date) and status != :fulfilled do
    today = store_today()

    if Date.diff(date, today) == 0,
      do: ~t"Today",
      else: Localize.DateTime.Relative.to_string!(date, relative_to: today, locale: locale) |> upcase_first()
  end

  defp fulfillment_relative(_date, _locale, _status), do: nil

  defp upcase_first(string) do
    {first, rest} = String.split_at(string, 1)
    String.upcase(first) <> rest
  end

  defp date_tone(date) do
    case Date.compare(date, store_today()) do
      :lt -> :overdue
      :eq -> :today
      :gt -> :upcoming
    end
  end

  defp relative_date_badge_class(:overdue), do: "admin-badge-error"
  defp relative_date_badge_class(:today), do: "admin-badge-success"

  defp store_today, do: DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

  # `position` is stored as a `"lat,lng"` string by HERE geocoding.
  defp parse_position(nil), do: nil

  defp parse_position(position) do
    case String.split(position, ",") do
      [lat, lng] -> {String.trim(lat), String.trim(lng)}
      _ -> nil
    end
  end

  # Mapbox Static Images API expects `lon,lat` ordering.
  defp mapbox_static_url({lat, lng}, token) do
    marker = "pin-s+e8542b(#{lng},#{lat})"
    center = "#{lng},#{lat},14"

    "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/" <>
      "#{marker}/#{center}/600x300@2x" <>
      "?access_token=#{token}&logo=false&attribution=false"
  end

  # Falls back to the typed address when an order hasn't been geocoded yet.
  defp directions_url({lat, lng}, _address), do: maps_dir_url("#{lat},#{lng}")

  defp directions_url(nil, address) when is_binary(address) and address != "",
    do: maps_dir_url(address)

  defp directions_url(_position, _address), do: nil

  defp maps_dir_url(destination) do
    "https://www.google.com/maps/dir/?api=1" <>
      "&origin=#{URI.encode_www_form(Edenflowers.Fulfillment.shop_address())}" <>
      "&destination=#{URI.encode_www_form(destination)}" <>
      "&travelmode=driving"
  end

  defp fastmail_search_url(email) do
    "https://app.fastmail.com/mail/search:#{URI.encode_www_form(email)}"
  end
end

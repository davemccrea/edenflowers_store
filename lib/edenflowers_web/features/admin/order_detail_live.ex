defmodule EdenflowersWeb.Admin.OrderDetailLive do
  @moduledoc """
  Admin order page for fulfillment, florist notes, cancellation, and payment actions.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.Drawers
  import EdenflowersWeb.Admin.OrderDetailComponents

  alias Edenflowers.Email.Preview
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments
  alias Edenflowers.PhoneNumber
  alias Edenflowers.ShopTime
  alias EdenflowersWeb.Admin.DrawerPreview
  alias EdenflowersWeb.Admin.Drawers
  alias EdenflowersWeb.Admin.EmailDrawer
  alias EdenflowersWeb.Admin.InvoicesLive
  alias EdenflowersWeb.Admin.OrderLog
  alias EdenflowersWeb.Admin.PaymentActions
  alias EdenflowersWeb.Admin.PhotoUpload
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @photo_field "fulfillment[photo]"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Orders.get_order_for_admin(id, actor: socket.assigns.current_user) do
      {:ok, %Order{} = order} ->
        if connected?(socket) do
          EdenflowersWeb.Endpoint.subscribe("order:changed:#{order.id}")
          EdenflowersWeb.Endpoint.subscribe("admin:orders")
          EdenflowersWeb.Endpoint.subscribe("admin:pass_it_on")
        end

        {:ok,
         socket
         |> assign(:page_title, ~t"Order #{order.order_reference}")
         |> assign(:locale, Localize.get_locale())
         |> assign(:mapbox_token, Application.get_env(:edenflowers, :mapbox_token))
         |> assign_order(order)
         |> assign(fulfillment_form: nil, photo_error: nil)
         |> assign(cancelling: nil, cancel_form: nil)
         |> assign(email_form: nil, email_kind: nil, preview: nil)
         |> assign(:settlement_mode, :settle)
         |> PhotoUpload.allow([@photo_field])
         |> assign(:queue, queue_position(order, socket.assigns.current_user))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Order not found.")
         |> push_navigate(to: ~p"/admin/orders")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header
          title={@order.customer_name || @order.order_reference}
          back={{~t"Orders", ~p"/admin/orders"}}
        >
          <:nav :if={@queue}>
            <.queue_nav queue={@queue} fulfilled={@order.fulfillment_status == :fulfilled} />
          </:nav>
          <:subtitle>
            <span class="flex flex-col gap-2.5">
              <span class="inline-flex flex-wrap items-center gap-x-2">
                <span class="tabular-nums">{@order.order_reference}</span>
                <span :if={@order.ordered_at} aria-hidden="true">·</span>
                <span :if={@order.ordered_at}>{Format.datetime(@order.ordered_at, @locale)}</span>
              </span>
              <%!-- Worded to stand alone, so the badges need no captions. --%>
              <span id="order-status" class="inline-flex flex-wrap items-center gap-1.5">
                <span :if={@order.payment_status}>
                  <span class="sr-only">{~t"Payment:"}</span>
                  <.payment_status_badge status={@order.payment_status} />
                </span>
                <span>
                  <span class="sr-only">{~t"Fulfillment:"}</span>
                  <.fulfillment_status_badge status={@order.fulfillment_status} method={@order.fulfillment_method} />
                </span>
                <.gift_badge
                  :if={@order.gift && !@order.gift_voucher_sale?}
                  recipient_name={presence(@order.recipient_name)}
                />
                <%!-- The order that started it too, not only its Occurrences. --%>
                <.subscription_badge
                  :if={@order.subscription_id}
                  navigate={~p"/admin/subscriptions/#{@order.subscription_id}"}
                />
                <.badge :if={@order.voucher_card_to_hand_over?} tone={:attention} icon="hero-pencil-square">
                  {~t"Card to write"}
                </.badge>
                <%!-- The payment card sits below the job on narrow screens; this says money is waiting there. --%>
                <.badge
                  :if={!@order.settled?}
                  href="#order-payment-summary"
                  tone={if Decimal.positive?(@order.balance), do: :warning, else: :error}
                  class="tabular-nums xl:hidden"
                >
                  {if Decimal.positive?(@order.balance),
                    do: ~t"To collect #{amount = Format.currency(@order.balance, @locale)}",
                    else: ~t"To refund #{amount = Format.currency(Decimal.abs(@order.balance), @locale)}"}
                  <.icon name="hero-arrow-down" class="h-3 w-3" />
                </.badge>
              </span>
            </span>
          </:subtitle>
          <:actions>
            <.button
              :if={@order.can_mark_ready?}
              type="button"
              phx-click="mark_ready"
              variant="primary"
              size="sm"
            >
              {~t"Mark as ready"}
            </.button>
            <.button
              :if={@order.can_undo_ready?}
              type="button"
              phx-click="undo_ready"
              variant="ghost"
              size="sm"
            >
              {~t"Undo ready"}
            </.button>
            <.button
              :if={@order.fulfillable?}
              type="button"
              phx-click="confirm_fulfillment"
              variant={if @order.can_mark_ready?, do: "secondary", else: "primary"}
              size="sm"
            >
              {if @order.fulfillment_method == :delivery, do: ~t"Mark as delivered", else: ~t"Mark as collected"}
            </.button>
            <.button
              :if={@order.editable?}
              navigate={~p"/admin/orders/#{@order.id}/edit"}
              variant="secondary"
              size="sm"
            >
              <.icon name="hero-pencil-square" class="h-4 w-4" /> {~t"Edit"}
            </.button>
          </:actions>
          <:menu>
            <.order_menu order={@order} locale={@locale} />
          </:menu>
        </.admin_page_header>

        <.confirm_fulfillment
          :if={@order.fulfillable?}
          form={@fulfillment_form}
          photo_error={@photo_error}
          order={@order}
          uploads={@uploads}
          preview={@preview}
        />
        <.cancel_drawer
          :if={@order.cancellable?}
          title={~t"Cancel order"}
          submit_label={~t"Cancel order"}
          keep_label={~t"Keep order"}
          form={@cancel_form}
          payable={@cancelling}
          email={@order.customer_email}
          locale={@locale}
          preview={@preview}
        />
        <.email_drawer
          form={@email_form}
          preview={@preview}
          {EmailDrawer.text(@email_kind, @order, @locale)}
        />
        <.settlement_drawer
          order={@order}
          mode={@settlement_mode}
          payment_form={@payment_form}
          refund_form={@refund_form}
          locale={@locale}
          preview={@preview}
        />

        <%!-- The job on the left, read at the bench; the money, people and history on the right, read at the desk. --%>
        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <div class="space-y-6">
            <.gift_voucher_sold
              :if={@order.gift_voucher_sale?}
              order={@order}
              voucher_form={@voucher_form}
              locale={@locale}
            />

            <.widget :if={!@order.gift_voucher_sale?} id="order-fulfillment-summary" title={~t"Fulfillment"}>
              <p
                :if={@order.can_undo_ready? && @order.ready_at}
                id="order-ready-at"
                class="text-base-content/75 mb-4 text-sm"
              >
                {~t"Marked ready #{at = Format.datetime(@order.ready_at, @locale)}"}
              </p>
              <div :if={@pickup_message_urls} id="order-ready-messages" class="mb-4">
                <.message_links
                  urls={@pickup_message_urls}
                  sms_label={~t"Text ready for pickup"}
                  whatsapp_label={~t"WhatsApp ready for pickup"}
                />
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
                <.summary_fact :if={Format.fulfillment_time_range(@order, @locale)} label={~t"Time"}>
                  <span id="order-fulfillment-time" class="tabular-nums">
                    {Format.fulfillment_time_range(@order, @locale)}
                  </span>
                </.summary_fact>
                <.summary_fact label={~t"Method"}>
                  <.fulfillment_method
                    method={@order.fulfillment_method}
                    label={present?(@order.fulfillment_option_name) && @order.fulfillment_option_name}
                    class="whitespace-normal"
                  />
                </.summary_fact>
              </div>

              <.delivery_location
                :if={@order.fulfillment_method == :delivery}
                position={parse_position(@order.position)}
                token={@mapbox_token}
                address={@order.delivery_address}
                distance_km={@order.distance_km}
              />

              <div
                :if={present?(@order.delivery_instructions)}
                class="bg-warning/15 border-base-content/12 mt-5 flex gap-2.5 border px-3 py-2.5"
              >
                <.icon name="hero-information-circle" class="text-warning-content mt-0.5 h-5 w-5 shrink-0" />
                <div>
                  <p class="text-warning-content text-sm font-semibold">{~t"Delivery instructions"}</p>
                  <p class="text-base-content mt-0.5 whitespace-pre-wrap break-words">{@order.delivery_instructions}</p>
                </div>
              </div>

              <div
                :if={@order.fulfillment_email_failed_at}
                id="order-confirmation-failed"
                class="bg-warning/15 border-base-content/12 mt-5 flex gap-2.5 border px-3 py-2.5"
              >
                <.icon name="hero-envelope" class="text-warning-content mt-0.5 h-5 w-5 shrink-0" />
                <div class="text-sm">
                  <p class="text-warning-content font-semibold">{~t"Couldn't email the confirmation."}</p>
                  <p class="text-base-content mt-0.5">
                    <%= if @order.email_delivery_photo do %>
                      {~t"Check the delivery photo below, then send it again from the menu."}
                    <% else %>
                      {~t"Check the error, then send it again from the menu."}
                    <% end %>
                    <.link href={~p"/admin/errors"} class="link link-primary">{~t"View errors"}</.link>
                  </p>
                </div>
              </div>

              <p :if={@order.delivery_photo_slug} id="order-delivery-photo" class="text-base-content/75 mt-5 text-sm">
                {~t"Nobody was home. The order was left here."}
                <a
                  href={image_url(@order.delivery_photo_slug, 1600, 1600, "fit")}
                  target="_blank"
                  rel="noopener"
                  class="link link-primary inline-flex items-center gap-1"
                >
                  {~t"View photo"}
                  <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" />
                </a>
              </p>
            </.widget>

            <.widget :if={!@order.gift_voucher_sale?} id="order-items" title={~t"To make"}>
              <.readonly_line_items line_items={Enum.reject(@order.line_items, & &1.is_card)} />
            </.widget>

            <.widget
              :if={
                !@order.gift_voucher_sale? and
                  (present?(@order.card_message) or Enum.any?(@order.line_items, & &1.is_card))
              }
              id="order-card"
              title={~t"Card to write"}
            >
              <div :if={Enum.any?(@order.line_items, & &1.is_card)} class="mb-4">
                <.readonly_line_items line_items={Enum.filter(@order.line_items, & &1.is_card)} />
              </div>
              <blockquote
                :if={present?(@order.card_message)}
                phx-no-format
                class="text-base-content font-serif whitespace-pre-wrap break-words text-xl italic leading-relaxed"
              >{@order.card_message}</blockquote>
            </.widget>

            <.widget id="order-florist-note" title={~t"Florist note"}>
              <.form for={@note_form} id="florist-note-form" phx-submit="save_florist_note" class="space-y-3">
                <.refusal form={@note_form} />
                <.input
                  field={@note_form[:florist_note]}
                  type="textarea"
                  rows="3"
                  aria-label={~t"Florist note"}
                  placeholder={~t"Only you see this."}
                  class="textarea w-full"
                />
                <.button type="submit" variant="secondary">{~t"Save note"}</.button>
              </.form>
            </.widget>
          </div>

          <%!-- Payment comes first beside the job, but after the contacts once stacked,
               since the badge in the header already points down to it. --%>
          <aside class="flex flex-col gap-6">
            <section
              id="order-payment-summary"
              class={["border p-4 sm:p-5 xl:order-first", if(!@order.settled?,
    do: "bg-warning/10 border-base-content/12",
    else: "bg-base-100 border-base-content/12")]}
            >
              <h2 class="text-base-content mb-4 text-base font-semibold">{~t"Payment"}</h2>
              <dl class="text-sm">
                <.money_row
                  :for={line_item <- @order.line_items}
                  label={line_label(line_item)}
                  amount={line_item.subtotal}
                  locale={@locale}
                />
                <.money_row
                  :if={positive?(@order.discount)}
                  ruled
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
                <.money_row
                  :if={!@order.gift_voucher_sale?}
                  label={~t"Fulfillment fee"}
                  amount={@order.fulfillment_fee}
                  locale={@locale}
                />
                <.money_row strong label={~t"Total"} amount={@order.grand_total} locale={@locale} />
                <.money_row muted label={~t"Includes VAT"} amount={@order.vat} locale={@locale} />
              </dl>
              <dl :if={@payments != []} id="order-payments" class="border-base-content/12 mt-1.5 border-t pt-2 text-sm">
                <.payment_row :for={payment <- @payments} payment={payment} locale={@locale} />
              </dl>

              <.balance_panel
                id="order-balance"
                record={@order}
                locale={@locale}
                class="mt-4"
              >
                <.payment_link_buttons
                  :if={Decimal.positive?(@order.balance) && !@order.gift_voucher_sale?}
                  order={@order}
                  locale={@locale}
                />
              </.balance_panel>
              <.payment_link
                :if={@order.payment_link_open? && Decimal.positive?(@order.balance) && !@order.gift_voucher_sale?}
                order={@order}
                payment_message_urls={@payment_message_urls}
              />
              <div
                :if={@order.invoices != [] || @order.invoiceable?}
                id="order-invoices"
                class="border-base-content/12 mt-4 border-t pt-3 text-sm"
              >
                <h3 class="text-base-content mb-2 font-semibold">{~t"Invoices"}</h3>
                <ul :if={@order.invoices != []} class="space-y-1.5">
                  <li :for={invoice <- @order.invoices} class="flex items-center justify-between gap-3">
                    <.link navigate={~p"/admin/invoices/#{invoice.id}"} class="link link-primary tabular-nums">
                      {if invoice.number, do: ~t"Invoice #{number = invoice.number}", else: ~t"Invoice draft"}
                    </.link>
                    <span class="flex items-center gap-2">
                      <span :if={invoice.number} class="tabular-nums">{Format.currency(invoice.amount, @locale)}</span>
                      <.badge tone={InvoicesLive.status_tone(invoice.status, invoice.overdue?)}>
                        {InvoicesLive.status_label(invoice.status, invoice.overdue?)}
                      </.badge>
                    </span>
                  </li>
                </ul>
                <.button
                  :if={@order.invoiceable?}
                  type="button"
                  phx-click="create_invoice"
                  variant="secondary"
                  size="sm"
                  class="mt-2"
                >
                  {~t"Create invoice"}
                </.button>
              </div>
              <div
                :if={@order.receipt_email_failed_at || @order.order_details_email_failed_at}
                id="order-email-failed"
                class="bg-warning/15 border-base-content/12 mt-4 flex gap-2.5 border px-3 py-2.5 text-sm"
              >
                <.icon name="hero-envelope" class="text-warning-content mt-0.5 h-5 w-5 shrink-0" />
                <div>
                  <p :if={@order.receipt_email_failed_at} class="text-warning-content font-semibold">
                    {~t"Couldn't email the receipt."}
                  </p>
                  <p :if={@order.order_details_email_failed_at} class="text-warning-content font-semibold">
                    {~t"Couldn't email the order details."}
                  </p>
                  <p class="text-base-content mt-0.5">
                    {~t"Check the error, then send it again from the menu."}
                    <.link href={~p"/admin/errors"} class="link link-primary">{~t"View errors"}</.link>
                  </p>
                </div>
              </div>
            </section>

            <.widget id="order-customer" title={~t"Customer"}>
              <.person_block>
                <:contact :if={@order.customer_email}>
                  <.email_link email={@order.customer_email} />
                </:contact>
                <:contact :if={present?(@order.customer_phone_number)}>
                  <.phone_link phone_number={@order.customer_phone_number} />
                </:contact>
                <:contact :if={present?(@order.customer_instagram)}>
                  <.instagram_link handle={@order.customer_instagram} />
                </:contact>
                <:contact :if={@order.user_id}>
                  <.link
                    id="order-customer-link"
                    navigate={~p"/admin/customers/#{@order.user_id}"}
                    class="link link-primary touch-target inline-flex items-center gap-1.5"
                  >
                    <.icon name="hero-user" class="h-3.5 w-3.5 shrink-0" />
                    {~t"View customer's orders"}
                  </.link>
                </:contact>
              </.person_block>
            </.widget>

            <.widget
              :if={
                (@order.gift && !@order.gift_voucher_sale? && present?(@order.recipient_name)) ||
                  @order.missing_delivery_phone?
              }
              id="order-recipient"
              title={~t"Recipient"}
            >
              <.person_block :if={@order.gift && present?(@order.recipient_name)} name={@order.recipient_name}>
                <:contact :if={present?(@order.recipient_phone_number)}>
                  <.phone_link phone_number={@order.recipient_phone_number} />
                </:contact>
              </.person_block>

              <div
                :if={@order.missing_delivery_phone?}
                id="order-missing-phone"
                class={["bg-warning/15 border-base-content/12 flex gap-2.5 border px-3 py-2.5", @order.gift && present?(@order.recipient_name) && "mt-5"]}
              >
                <.icon name="hero-phone-x-mark" class="text-warning-content mt-0.5 h-5 w-5 shrink-0" />
                <p class="text-warning-content text-sm font-semibold">{~t"Missing recipient phone"}</p>
              </div>
            </.widget>

            <.pass_it_on_card
              :if={@order.pass_it_on_shown?}
              order={@order}
              locale={@locale}
            />

            <.widget id="order-log" title={~t"History"}>
              <.history_timeline id="order-history" entries={@log} locale={@locale}>
                <:details :let={entry}>
                  <dl class="mt-2 space-y-2">
                    <div :for={{label, value} <- entry.details}>
                      <dt :if={label} class="text-base-content/75 text-xs">{label}</dt>
                      <dd class="text-base-content/85 break-words">
                        <ul :if={is_list(value)}>
                          <li :for={item <- value}>{item}</li>
                        </ul>
                        <span :if={!is_list(value)} class="whitespace-pre-line">{value}</span>
                      </dd>
                    </div>
                  </dl>
                </:details>
              </.history_timeline>
            </.widget>
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("mark_ready", _params, socket) do
    result = Orders.mark_order_ready(socket.assigns.order, actor: socket.assigns.current_user)
    {:noreply, readiness_result(socket, result, ~t"Order marked as ready.")}
  end

  def handle_event("undo_ready", _params, socket) do
    result = Orders.undo_order_ready(socket.assigns.order, actor: socket.assigns.current_user)
    {:noreply, readiness_result(socket, result, ~t"Order returned to To make.")}
  end

  def handle_event("confirm_fulfillment", _params, socket) do
    # "customer_home" starts as the unanswered radio posts it, so ticking
    # the email box first isn't taken for an answer.
    form =
      socket.assigns.order
      |> AshPhoenix.Form.for_update(:mark_fulfilled,
        as: "fulfillment",
        actor: socket.assigns.current_user,
        params: %{"customer_home" => "", "email_customer?" => email_by_default(socket.assigns.order, nil)},
        transform_params: &fulfillment_params/3
      )
      |> to_form()

    {:noreply,
     socket
     |> PhotoUpload.forget([@photo_field])
     |> assign(fulfillment_form: form, photo_error: nil)
     |> assign_fulfillment_preview()
     |> push_event("js-exec", %{to: "#confirm-fulfillment", attr: "phx-show"})}
  end

  def handle_event("cancel_fulfillment", _params, socket) do
    {:noreply, socket |> PhotoUpload.forget([@photo_field]) |> assign(:fulfillment_form, nil)}
  end

  # Answering "Was the customer home?" picks the email default again; ticking
  # the box by hand otherwise sticks.
  def handle_event("validate_fulfillment", %{"fulfillment" => params}, socket) do
    params =
      if params["customer_home"] == socket.assigns.fulfillment_form[:customer_home].value,
        do: params,
        else: Map.put(params, "email_customer?", email_by_default(socket.assigns.order, params["customer_home"]))

    {:noreply,
     socket
     |> assign(:fulfillment_form, AshPhoenix.Form.validate(socket.assigns.fulfillment_form, params))
     |> assign_fulfillment_preview()}
  end

  def handle_event("mark_fulfilled", %{"fulfillment" => %{"customer_home" => "false"} = params}, socket) do
    basename = Calendar.strftime(ShopTime.now(), "%Y%m%d-%H%M%S_") <> socket.assigns.order.order_reference
    socket = PhotoUpload.store_uploads(socket, [@photo_field], basename)

    case socket.assigns.photo_slugs[@photo_field] do
      nil -> {:noreply, assign(socket, :photo_error, ~t"Take a photo of where you left the order.")}
      slug -> mark_fulfilled(socket, Map.put(params, "delivery_photo_slug", slug))
    end
  end

  def handle_event("mark_fulfilled", %{"fulfillment" => params}, socket), do: mark_fulfilled(socket, params)

  def handle_event("save_florist_note", %{"note" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.note_form, params: params) do
      {:ok, order} -> {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:success, ~t"Note saved.")}
      {:error, form} -> {:noreply, assign(socket, :note_form, form)}
    end
  end

  def handle_event("link_card", %{"code" => code}, socket) do
    %{order: order, current_user: actor} = socket.assigns

    case Orders.link_pass_it_on_card(order, code, actor: actor) do
      {:ok, order} -> {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:success, ~t"Card linked.")}
      {:error, error} -> {:noreply, put_flash(socket, :error, card_error(error))}
    end
  end

  def handle_event("unlink_card", _params, socket) do
    %{order: order, current_user: actor} = socket.assigns

    case Orders.remove_pass_it_on_card(order, actor: actor) do
      {:ok, order} ->
        {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:success, ~t"Card removed.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, card_error(error))}
    end
  end

  def handle_event("open_cancel", _params, socket) do
    order = PaymentActions.load_for_cancel(socket.assigns.order)
    form = PaymentActions.cancel_form(order, socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(cancelling: order, cancel_form: form)
     |> assign_preview(:cancelled, form)
     |> push_event("js-exec", %{to: "#cancel-drawer", attr: "phx-show"})}
  end

  def handle_event("close_cancel", _params, socket) do
    {:noreply, assign(socket, cancelling: nil, cancel_form: nil)}
  end

  def handle_event("validate_cancel", %{"cancel" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.cancel_form, params)
    {:noreply, socket |> assign(:cancel_form, form) |> assign_preview(:cancelled, form)}
  end

  def handle_event("submit_cancel", %{"cancel" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.cancel_form, params: params) do
      {:ok, order} ->
        {:noreply,
         socket
         |> assign_order(reload(order, socket))
         |> assign(cancelling: nil, cancel_form: nil)
         |> push_event("js-exec", %{to: "#cancel-drawer", attr: "phx-hide"})
         |> put_flash(:success, ~t"Order cancelled.")}

      {:error, form} ->
        {:noreply, assign(socket, :cancel_form, form)}
    end
  end

  def handle_event("change_payment", %{"payment" => params} = event, socket) do
    %{payment_form: form, current_user: actor} = socket.assigns
    form = PaymentActions.change_payment_form(form, params, event["_target"], actor)
    {:noreply, socket |> assign(:payment_form, form) |> assign_preview(:payment, form)}
  end

  # Money owed back, or the menu's Refund, opens the refund form.
  def handle_event("open_settlement", params, socket) do
    mode =
      if params["mode"] == "refund" or socket.assigns.order.to_refund?,
        do: :refund,
        else: :settle

    {:noreply,
     socket
     |> assign(:settlement_mode, mode)
     |> assign_preview(
       if(mode == :refund, do: :refunded, else: :payment),
       if(mode == :refund, do: socket.assigns.refund_form, else: socket.assigns.payment_form)
     )
     |> push_event("js-exec", %{to: "#settlement-drawer", attr: "phx-show"})}
  end

  def handle_event("record_payment", %{"payment" => params}, socket) do
    result = PaymentActions.submit(socket.assigns.payment_form, params)
    {:noreply, settlement_result(socket, :payment_form, result)}
  end

  def handle_event("change_refund", %{"refund" => params} = event, socket) do
    form = PaymentActions.change_refund_form(socket.assigns.refund_form, params, event["_target"])
    {:noreply, socket |> assign(:refund_form, form) |> assign_preview(:refunded, form)}
  end

  def handle_event("refund", %{"refund" => params}, socket) do
    result = PaymentActions.submit(socket.assigns.refund_form, params)
    {:noreply, settlement_result(socket, :refund_form, result)}
  end

  def handle_event("undo_payment", %{"id" => payment_id}, socket) do
    result = PaymentActions.undo_payment(socket.assigns.order, payment_id, socket.assigns.current_user)
    {:noreply, flash_payment_result(socket, result)}
  end

  def handle_event("open_payment_link", _params, socket) do
    result = PaymentActions.open_payment_link(socket.assigns.order, socket.assigns.current_user)
    {:noreply, flash_payment_result(socket, result)}
  end

  def handle_event("create_invoice", _params, socket) do
    case Payments.create_invoice_for_order(socket.assigns.order.id, actor: socket.assigns.current_user) do
      {:ok, invoice} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/invoices/#{invoice.id}")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign_order(reload(socket.assigns.order, socket))
         |> put_flash(:error, ~t"This order can't be invoiced now.")}
    end
  end

  def handle_event("change_voucher_last_day", %{"voucher" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.voucher_form, params: params) do
      {:ok, _voucher} ->
        {:noreply,
         socket |> assign_order(reload(socket.assigns.order, socket)) |> put_flash(:success, ~t"Last day changed.")}

      {:error, form} ->
        {:noreply, assign(socket, :voucher_form, form)}
    end
  end

  def handle_event("open_email", %{"kind" => kind}, socket) do
    {:noreply, EmailDrawer.open(socket, kind, socket.assigns.order)}
  end

  def handle_event("close_email", _params, socket) do
    {:noreply, EmailDrawer.close(socket)}
  end

  def handle_event("validate_email", %{"email" => params}, socket) do
    {:noreply, EmailDrawer.validate(socket, params)}
  end

  def handle_event("send_email", %{"email" => params}, socket) do
    case EmailDrawer.submit(socket, params) do
      {:ok, socket} ->
        {:noreply,
         socket
         |> put_flash(:success, sent_message(socket.assigns.email_kind))
         |> EmailDrawer.close()
         |> assign_order(reload(socket.assigns.order, socket))}

      {:error, socket} ->
        {:noreply, put_flash(socket, :error, failed_message(socket.assigns.email_kind))}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "order:changed:" <> _, event: event}, socket) do
    socket = assign_order(socket, reload(socket.assigns.order, socket))

    case email_failed_message(event) do
      nil -> {:noreply, socket}
      message -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  # Redemptions and scans change the chain without changing the order being viewed.
  def handle_info(%Phoenix.Socket.Broadcast{topic: topic, payload: %{data: changed}}, socket)
      when topic in ["admin:orders", "admin:pass_it_on"] do
    socket =
      if socket.assigns.order.pass_it_on_shown? and chain_changed?(socket.assigns.order.pass_it_on_chain, changed),
        do: assign(socket, :order, reload(socket.assigns.order, socket)),
        else: socket

    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp chain_changed?(chain, %Order{id: id, promotion_id: promotion_id}) do
    Enum.any?(chain, fn link ->
      link.id == id or match?(%{id: ^promotion_id} when not is_nil(promotion_id), link.pass_it_on_card)
    end)
  end

  defp chain_changed?(chain, %Edenflowers.Pricing.Promotion{id: id, gift_order_id: gift_order_id}) do
    Enum.any?(chain, fn link ->
      link.id == gift_order_id or link.promotion_id == id or match?(%{id: ^id}, link.pass_it_on_card)
    end)
  end

  # Reloads on an error too: a payment can be recorded while its receipt failed to send.
  defp flash_payment_result(socket, {kind, message}) do
    socket
    |> assign_order(reload(socket.assigns.order, socket))
    |> put_flash(kind, message)
  end

  # The drawer closes once the money is recorded. On an error it stays open with
  # the form as Jennie filled it in and the refusal on its fields.
  defp settlement_result(socket, _form, {:ok, result}) do
    socket
    |> flash_payment_result(result)
    |> push_event("js-exec", %{to: "#settlement-drawer", attr: "phx-hide"})
  end

  defp settlement_result(socket, form_key, {:error, form}), do: assign(socket, form_key, form)

  defp email_failed_message("record_fulfillment_email_failure"), do: ~t"Couldn't email the confirmation."
  defp email_failed_message("record_receipt_email_failure"), do: ~t"Couldn't email the receipt."
  defp email_failed_message("record_order_details_email_failure"), do: ~t"Couldn't email the order details."
  defp email_failed_message(_event), do: nil

  # Worth an email only when the customer didn't see it arrive: a gift, or an
  # order left while nobody was home.
  defp email_by_default(%{gift: true}, _customer_home), do: "true"
  defp email_by_default(_order, "false"), do: "true"
  defp email_by_default(_order, _customer_home), do: "false"

  defp mark_fulfilled(socket, params) do
    case AshPhoenix.Form.submit(socket.assigns.fulfillment_form, params: params) do
      {:ok, order} ->
        message =
          if order.fulfillment_method == :delivery,
            do: ~t"Order marked as delivered.",
            else: ~t"Order marked as collected."

        message =
          if params["email_customer?"] != "false" && order.customer_email,
            do: message <> " " <> ~t"Confirmation queued.",
            else: message

        {:noreply,
         socket
         |> assign_order(reload(order, socket))
         |> assign(:fulfillment_form, nil)
         |> put_flash(:success, message)}

      {:error, form} ->
        {:noreply, assign(socket, :fulfillment_form, form)}
    end
  end

  # Left where nobody was home, the order is photographed and the photo goes
  # with the email. "customer_home" itself is the drawer's alone.
  defp fulfillment_params(form, %{"customer_home" => "false"} = params, action),
    do: Drawers.keep_email_edits(form, Map.put(params, "email_delivery_photo", "true"), action)

  defp fulfillment_params(form, params, action), do: Drawers.keep_email_edits(form, params, action)

  defp assign_order(socket, order) do
    payments = payments(order)
    actor = socket.assigns.current_user

    socket
    |> assign(:order, order)
    |> assign(:pickup_message_urls, pickup_message_urls(order))
    |> assign(:payment_message_urls, payment_message_urls(order))
    |> assign(
      :note_form,
      order |> AshPhoenix.Form.for_update(:update_florist_note, as: "note", actor: actor) |> to_form()
    )
    |> assign(:payment_form, if(order.to_collect?, do: PaymentActions.payment_form(order, actor)))
    |> assign(:refund_form, if(order.refundable?, do: PaymentActions.refund_form(order, actor)))
    |> assign(:voucher_form, voucher_form(order, actor))
    |> assign(:payments, payments)
    |> assign(:log, order_log(order, payments, socket.assigns.locale))
  end

  defp voucher_form(%{gift_voucher_line: %{gift_voucher: %{last_day_changeable?: true} = voucher}}, actor),
    do: voucher |> AshPhoenix.Form.for_update(:change_last_day, as: "voucher", actor: actor) |> to_form()

  defp voucher_form(_order, _actor), do: nil

  defp payments(order) do
    order
    |> Ash.load!([payments: [:undoable?]], authorize?: false)
    |> Map.fetch!(:payments)
  end

  defp order_log(order, payments, locale) do
    order =
      Ash.load!(order, :paper_trail_versions, authorize?: false)

    OrderLog.entries(order.paper_trail_versions, payments, locale, order.gift_voucher_sale?)
  end

  defp readiness_result(socket, {:ok, order}, message) do
    socket |> assign_order(reload(order, socket)) |> put_flash(:success, message)
  end

  defp readiness_result(socket, {:error, _error}, _message) do
    socket
    |> assign_order(reload(socket.assigns.order, socket))
    |> put_flash(:error, ~t"The order has changed. Check its status and try again.")
  end

  defp reload(order, socket), do: Orders.get_order_for_admin!(order.id, actor: socket.assigns.current_user)

  # LinkPassItOnCard words its own errors about the card; the rest are the order's state.
  defp card_error(%{errors: [%{field: :code, message: message} | _]}), do: message

  defp card_error(_error),
    do: ~t"The card can't change now: the gift has been delivered or cancelled, or its recipient opened the card."

  defp sent_message(:order_details), do: ~t"Order details sent."
  defp sent_message(:gift_voucher), do: ~t"Gift voucher sent."
  defp sent_message(:receipt), do: ~t"Receipt sent."
  defp sent_message(:fulfillment), do: ~t"Confirmation queued."
  defp sent_message(:payment_reminder), do: ~t"Payment reminder sent."

  defp failed_message(:gift_voucher), do: ~t"Could not send the gift voucher. Check the address and try again."
  defp failed_message(:receipt), do: ~t"Could not send the receipt. Try again in a moment."
  defp failed_message(:fulfillment), do: ~t"Could not queue the confirmation."
  defp failed_message(_kind), do: ~t"Could not send the email. Try again in a moment."

  # Nothing to preview when the order has nothing to settle that way.
  defp assign_preview(socket, _kind, nil), do: assign(socket, :preview, nil)

  defp assign_preview(socket, kind, form),
    do: assign(socket, :preview, DrawerPreview.build(kind, socket.assigns.order, form))

  defp assign_fulfillment_preview(socket) do
    photo? = socket.assigns.fulfillment_form[:customer_home].value == "false"
    assign(socket, :preview, Preview.build(:fulfillment, socket.assigns.order, %{photo?: photo?}))
  end

  # Muted rows inherit the row's own muted tone.

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

  defp pickup_message_urls(%{pickup_message_sendable?: true} = order) do
    message_urls(order.customer_phone_number, pickup_message(order))
  end

  defp pickup_message_urls(_order), do: nil

  defp payment_message_urls(order) do
    if order.payment_link_open?,
      do: message_urls(order.customer_phone_number, payment_message(order)),
      else: nil
  end

  # Links that open Jennie's own messaging app with the message written; she sends it.
  defp message_urls(phone_number, message) do
    case PhoneNumber.format(phone_number, :e164) do
      {:ok, e164} ->
        body = URI.encode(message, &URI.char_unreserved?/1)

        # iOS reads `&body=`, Android reads `?body=`; `?&body=` satisfies both.
        %{
          sms: "sms:#{e164}?&body=#{body}",
          whatsapp: "https://wa.me/#{String.trim_leading(e164, "+")}?text=#{body}"
        }

      :error ->
        nil
    end
  end

  # Written in the customer's language, not the admin's.
  # Sent the day Jennie finishes it, so "today" is the day she sends it. On a
  # Sunday the shop is shut, so there are no opening hours to give.
  defp pickup_message(order) do
    today = Edenflowers.ShopTime.today()

    message =
      EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
        name = order.customer_first_name
        reference = order.order_reference

        case EdenflowersWeb.Business.opening_hours(today) do
          nil ->
            ~t"Hi #{name}, your Eden Flowers order #{reference} is now ready for pick up."

          {opens, closes} ->
            ~t"Hi #{name}, your Eden Flowers order #{reference} is now ready for pick up. Minimossen is open from #{opening_time = Format.time(opens, order.locale)} to #{closing_time = Format.time(closes, order.locale)} today. If that doesn't suit, just let me know."
        end
      end)

    message <> "\nJennie / Eden Flowers"
  end

  defp payment_message(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      amount = Format.currency(order.balance, order.locale)
      url = EdenflowersWeb.PaymentLink.url_for(order)

      ~t"Hi #{order.customer_first_name}, you can pay #{amount} for your Eden Flowers order #{order.order_reference} here: #{url}"
    end)
  end
end

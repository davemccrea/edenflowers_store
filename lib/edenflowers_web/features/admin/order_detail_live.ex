defmodule EdenflowersWeb.Admin.OrderDetailLive do
  @moduledoc """
  Admin order page for fulfillment, florist notes, cancellation, and payment actions.
  """

  use EdenflowersWeb, :live_view

  require Logger

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.PhotoUpload, only: [photo_input: 1]

  alias Edenflowers.Email.Preview
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.PhoneNumber
  alias Edenflowers.ShopTime
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
        if connected?(socket), do: EdenflowersWeb.Endpoint.subscribe("order:changed:#{order.id}")

        {:ok,
         socket
         |> assign(:page_title, ~t"Order #{order.order_reference}")
         |> assign(:locale, Localize.get_locale())
         |> assign(:mapbox_token, Application.get_env(:edenflowers, :mapbox_token))
         |> assign_order(order)
         |> assign(:fulfillment_form, nil)
         |> assign(:fulfillment_error, nil)
         |> assign(cancel_form: nil, cancel_error: nil)
         |> assign(email_form: nil, email_kind: nil, preview: nil)
         |> assign(settlement_mode: :settle, settlement_error: nil)
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
                <span :if={@order.fulfillment_status != :pending}>
                  <span class="sr-only">{~t"Fulfillment:"}</span>
                  <.fulfillment_status_badge status={@order.fulfillment_status} />
                </span>
                <.gift_badge :if={@order.gift} recipient_name={presence(@order.recipient_name)} />
                <.subscription_badge :if={@order.origin == :subscription} />
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
              :if={@order.fulfillable?}
              type="button"
              phx-click="confirm_fulfillment"
              variant="primary"
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
            <.order_menu order={@order} payments={@payments} locale={@locale} />
          </:menu>
        </.admin_page_header>

        <.confirm_fulfillment
          :if={@order.fulfillable?}
          form={@fulfillment_form}
          error={@fulfillment_error}
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
          error={@cancel_error}
          email={@order.customer_email}
          locale={@locale}
          preview={@preview}
          swedish_toggle?={swedish_toggle?(@order)}
        />
        <.email_drawer
          form={@email_form}
          preview={@preview}
          swedish_toggle?={swedish_toggle?(@order)}
          {email_drawer_text(@email_kind, @order, @locale)}
        />
        <.settlement_drawer
          order={@order}
          mode={@settlement_mode}
          error={@settlement_error}
          payment_params={@payment_params}
          refund_params={@refund_params}
          locale={@locale}
          preview={@preview}
        />

        <%!-- The job on the left, read at the bench; the money, people and history on the right, read at the desk. --%>
        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <div class="space-y-6">
            <.widget id="order-fulfillment-summary" title={~t"Fulfillment"}>
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
                    <.link navigate={~p"/admin/errors"} class="link link-primary">{~t"View errors"}</.link>
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

            <.widget id="order-items" title={~t"To make"}>
              <.readonly_line_items line_items={Enum.reject(@order.line_items, & &1.is_card)} />
            </.widget>

            <.widget
              :if={present?(@order.card_message) or Enum.any?(@order.line_items, & &1.is_card)}
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
                <.payment_link_buttons :if={Decimal.positive?(@order.balance)} order={@order} locale={@locale} />
              </.balance_panel>
              <.payment_link
                :if={@order.payment_link_open? && Decimal.positive?(@order.balance)}
                order={@order}
                payment_message_urls={@payment_message_urls}
              />
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
                    <.link navigate={~p"/admin/errors"} class="link link-primary">{~t"View errors"}</.link>
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
                <:contact :if={
                  !present?(@order.customer_phone_number) && customer_phone?(@order) &&
                    present?(@order.recipient_phone_number)
                }>
                  <.phone_link phone_number={@order.recipient_phone_number} />
                </:contact>
                <:contact :if={@pickup_message_urls}>
                  <.message_links
                    urls={@pickup_message_urls}
                    sms_label={~t"Text ready for pickup"}
                    whatsapp_label={~t"WhatsApp ready for pickup"}
                  />
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
              :if={(@order.gift && present?(@order.recipient_name)) || @order.missing_delivery_phone?}
              id="order-recipient"
              title={~t"Recipient"}
            >
              <.person_block :if={@order.gift && present?(@order.recipient_name)} name={@order.recipient_name}>
                <:contact :if={
                  (present?(@order.customer_phone_number) || !customer_phone?(@order)) &&
                    present?(@order.recipient_phone_number)
                }>
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

            <.widget id="order-log" title={~t"History"}>
              <ol class="divide-base-content/12 divide-y text-sm">
                <.history_entry
                  :for={{entry, index} <- Enum.with_index(@log)}
                  id={"order-log-entry-#{index}"}
                  title={entry.title}
                  at={entry.at}
                  locale={@locale}
                >
                  <:details :if={entry.details != []}>
                    <dl class="border-base-content/12 mt-1.5 mb-1 ml-0.5 space-y-2 border-l pl-3">
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
                </.history_entry>
              </ol>
            </.widget>
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :order, Order, required: true
  attr :mode, :atom, required: true, values: [:settle, :refund]
  attr :error, :string, default: nil
  attr :payment_params, :map, required: true
  attr :refund_params, :map, required: true
  attr :locale, :string, required: true
  attr :preview, Swoosh.Email, default: nil

  defp settlement_drawer(assigns) do
    assigns = assign(assigns, :collect?, Decimal.positive?(assigns.order.balance))

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
            <dt class="text-base-content/75">{if @collect?, do: ~t"To collect", else: ~t"To refund"}</dt>
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
          :if={@mode == :settle and @collect?}
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

  defp settlement_title(_order, :refund), do: ~t"Refund"
  defp settlement_title(_order, :settle), do: ~t"Record payment"

  defp nothing_to_settle?(order, :refund), do: not order.refundable?
  defp nothing_to_settle?(order, :settle), do: not Decimal.positive?(order.balance)

  attr :form, :any, default: nil
  attr :error, :string, default: nil
  attr :order, Order, required: true
  attr :uploads, :map, required: true
  attr :preview, Swoosh.Email, default: nil

  defp confirm_fulfillment(assigns) do
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

  @impl true
  def handle_event("confirm_fulfillment", _params, socket) do
    # "customer_home" starts as the unanswered radio posts it, so ticking
    # the email box first isn't taken for an answer.
    form =
      to_form(
        %{
          "customer_home" => "",
          "email_customer" => email_by_default(socket.assigns.order, nil)
        },
        as: :fulfillment
      )

    {:noreply,
     socket
     |> PhotoUpload.forget([@photo_field])
     |> assign(:fulfillment_form, form)
     |> assign(:fulfillment_error, nil)
     |> assign_fulfillment_preview(form.params)
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
        else: Map.put(params, "email_customer", email_by_default(socket.assigns.order, params["customer_home"]))

    {:noreply,
     socket
     |> assign(:fulfillment_form, to_form(params, as: :fulfillment))
     |> assign_fulfillment_preview(params)}
  end

  def handle_event("mark_fulfilled", %{"fulfillment" => %{"customer_home" => "false"} = params}, socket) do
    basename = Calendar.strftime(ShopTime.now(), "%Y%m%d-%H%M%S_") <> socket.assigns.order.order_reference
    socket = PhotoUpload.store_uploads(socket, [@photo_field], basename)

    case socket.assigns.photo_slugs[@photo_field] do
      nil ->
        {:noreply, assign(socket, :fulfillment_error, ~t"Take a photo of where you left the order.")}

      slug ->
        mark_fulfilled(socket, %{
          delivery_photo_slug: slug,
          email_delivery_photo: true,
          email_customer?: params["email_customer"] != "false",
          message: params["message"]
        })
    end
  end

  def handle_event("mark_fulfilled", %{"fulfillment" => params}, socket) do
    mark_fulfilled(socket, %{email_customer?: params["email_customer"] != "false", message: params["message"]})
  end

  def handle_event("save_florist_note", %{"note" => %{"florist_note" => note}}, socket) do
    case Orders.update_florist_note(socket.assigns.order, %{florist_note: note}, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:info, ~t"Note saved.")}

      {:error, error} ->
        Logger.error("Florist note for order #{socket.assigns.order.id} not saved: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"Could not save the note.")}
    end
  end

  def handle_event("open_cancel", _params, socket) do
    form = PaymentActions.cancel_form(socket.assigns.order)

    {:noreply,
     socket
     |> assign(cancel_form: form, cancel_error: nil)
     |> assign_preview(:cancelled, form.params)
     |> push_event("js-exec", %{to: "#cancel-drawer", attr: "phx-show"})}
  end

  def handle_event("close_cancel", _params, socket) do
    {:noreply, assign(socket, cancel_form: nil, cancel_error: nil)}
  end

  def handle_event("validate_cancel", %{"cancel" => params}, socket) do
    {:noreply, socket |> assign(:cancel_form, to_form(params, as: :cancel)) |> assign_preview(:cancelled, params)}
  end

  def handle_event("submit_cancel", %{"cancel" => params}, socket) do
    socket = assign(socket, :cancel_form, to_form(params, as: :cancel))

    case PaymentActions.cancel(socket.assigns.order, params, socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply,
         socket
         |> assign_order(reload(order, socket))
         |> assign(cancel_form: nil, cancel_error: nil)
         |> push_event("js-exec", %{to: "#cancel-drawer", attr: "phx-hide"})
         |> put_flash(:info, ~t"Order cancelled.")}

      {:error, message} ->
        {:noreply, assign(socket, :cancel_error, message)}
    end
  end

  def handle_event("delete_order", _params, socket) do
    case Orders.delete_custom_order(socket.assigns.order, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply, socket |> put_flash(:info, ~t"Order deleted.") |> push_navigate(to: ~p"/admin/orders")}

      # Says why, e.g. a payment still under way.
      {:error, %{errors: [%{message: message} | _]}} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, error} ->
        Logger.error("Order #{socket.assigns.order.id} not deleted: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"Could not delete the order.")}
    end
  end

  def handle_event("change_payment", %{"payment" => params}, socket) do
    {:noreply, socket |> assign(:payment_params, params) |> assign_preview(:payment, params)}
  end

  # Money owed back, or the menu's Refund, opens the refund form.
  def handle_event("open_settlement", params, socket) do
    mode =
      if params["mode"] == "refund" or Decimal.negative?(socket.assigns.order.balance),
        do: :refund,
        else: :settle

    {:noreply,
     socket
     |> assign(settlement_mode: mode, settlement_error: nil)
     |> assign_preview(if(mode == :refund, do: :refunded, else: :payment), %{})
     |> push_event("js-exec", %{to: "#settlement-drawer", attr: "phx-show"})}
  end

  def handle_event("record_payment", %{"payment" => params}, socket) do
    result = PaymentActions.record_payment(socket.assigns.order, params, socket.assigns.current_user)
    {:noreply, socket |> assign(:payment_params, params) |> settlement_result(result)}
  end

  def handle_event("change_refund", %{"refund" => params} = event, socket) do
    params = PaymentActions.refund_params(params, event["_target"])

    {:noreply, socket |> assign(:refund_params, params) |> assign_preview(:refunded, params)}
  end

  def handle_event("refund", %{"refund" => params}, socket) do
    result = PaymentActions.refund(socket.assigns.order, params, socket.assigns.current_user)
    {:noreply, socket |> assign(:refund_params, params) |> settlement_result(result)}
  end

  def handle_event("undo_payment", %{"id" => payment_id}, socket) do
    result = PaymentActions.undo_payment(socket.assigns.order, payment_id, socket.assigns.current_user)
    {:noreply, flash_payment_result(socket, result)}
  end

  def handle_event("open_payment_link", _params, socket) do
    result = PaymentActions.open_payment_link(socket.assigns.order, socket.assigns.current_user)
    {:noreply, flash_payment_result(socket, result)}
  end

  def handle_event("open_email", %{"kind" => kind}, socket) do
    {:noreply,
     socket
     |> assign(email_kind: String.to_existing_atom(kind), email_form: to_form(%{"message" => ""}, as: :email))
     |> assign_preview(String.to_existing_atom(kind), %{})
     |> push_event("js-exec", %{to: "#email-drawer", attr: "phx-show"})}
  end

  def handle_event("close_email", _params, socket) do
    {:noreply, assign(socket, email_form: nil, email_kind: nil)}
  end

  def handle_event("validate_email", %{"email" => params}, socket) do
    {:noreply,
     socket
     |> assign(:email_form, to_form(params, as: :email))
     |> assign_preview(socket.assigns.email_kind, params)}
  end

  def handle_event("send_email", %{"email" => %{"message" => message}}, socket) do
    %{order: order, email_kind: kind, current_user: actor} = socket.assigns

    {flash, text} = send_email(kind, order, message, actor)

    {:noreply,
     socket
     |> assign_order(reload(order, socket))
     |> assign(email_form: nil, email_kind: nil)
     |> push_event("js-exec", %{to: "#email-drawer", attr: "phx-hide"})
     |> put_flash(flash, text)}
  end

  def handle_event("fetch_stripe_refunds", _params, socket) do
    case Edenflowers.Payments.sync_refunds(socket.assigns.order) do
      {:ok, 0} ->
        {:noreply, put_flash(socket, :info, ~t"No new refunds in Stripe.")}

      {:ok, _recorded} ->
        {:noreply,
         socket
         |> assign_order(reload(socket.assigns.order, socket))
         |> put_flash(:info, ~t"Refunds from Stripe recorded.")}

      {:error, reason} ->
        Logger.error("Fetching Stripe refunds for order #{socket.assigns.order.id} failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, ~t"Could not fetch refunds from Stripe. Try again in a moment.")}
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

  def handle_info(_message, socket), do: {:noreply, socket}

  # Reloads on an error too: a payment can be recorded while its receipt failed to send.
  defp flash_payment_result(socket, {kind, message}) do
    socket
    |> assign_order(reload(socket.assigns.order, socket))
    |> put_flash(kind, message)
  end

  # The drawer closes once the money is recorded. On an error it stays open with
  # the message and the forms as Jennie filled them in, which reloading would clear.
  defp settlement_result(socket, {:info, _message} = result) do
    socket
    |> flash_payment_result(result)
    |> assign(:settlement_error, nil)
    |> push_event("js-exec", %{to: "#settlement-drawer", attr: "phx-hide"})
  end

  defp settlement_result(socket, {:error, message}) do
    %{payment_params: payment_params, refund_params: refund_params} = socket.assigns

    socket
    |> assign_order(reload(socket.assigns.order, socket))
    |> assign(payment_params: payment_params, refund_params: refund_params, settlement_error: message)
  end

  defp email_failed_message("record_fulfillment_email_failure"), do: ~t"Couldn't email the confirmation."
  defp email_failed_message("record_receipt_email_failure"), do: ~t"Couldn't email the receipt."
  defp email_failed_message("record_order_details_email_failure"), do: ~t"Couldn't email the order details."
  defp email_failed_message(_event), do: nil

  # Worth an email only when the customer didn't see it arrive: a gift, or an
  # order left while nobody was home.
  defp email_by_default(%{gift: true}, _customer_home), do: "true"
  defp email_by_default(_order, "false"), do: "true"
  defp email_by_default(_order, _customer_home), do: "false"

  defp mark_fulfilled(socket, attrs) do
    case Orders.mark_order_fulfilled(socket.assigns.order, attrs, actor: socket.assigns.current_user) do
      {:ok, order} ->
        message =
          if order.fulfillment_method == :delivery,
            do: ~t"Order marked as delivered.",
            else: ~t"Order marked as collected."

        message =
          if attrs.email_customer? && order.customer_email,
            do: message <> " " <> ~t"Confirmation queued.",
            else: message

        {:noreply,
         socket
         |> assign_order(reload(order, socket))
         |> assign(:fulfillment_form, nil)
         |> put_flash(:info, message)}

      {:error, error} ->
        Logger.error("Order #{socket.assigns.order.id} not marked fulfilled: #{inspect(error)}")
        {:noreply, assign(socket, :fulfillment_error, ~t"Could not mark order as fulfilled.")}
    end
  end

  defp assign_order(socket, order) do
    payments = payments(order)

    socket
    |> assign(:order, order)
    |> assign(:pickup_message_urls, pickup_message_urls(order))
    |> assign(:payment_message_urls, payment_message_urls(order))
    |> assign(:note_form, to_form(%{"florist_note" => order.florist_note}, as: :note))
    |> assign(:payment_params, %{})
    |> assign(:refund_params, %{})
    |> assign(:payments, payments)
    |> assign(:log, order_log(order, payments, socket.assigns.locale))
  end

  defp payments(order) do
    order
    |> Ash.load!([payments: [:undoable?]], authorize?: false)
    |> Map.fetch!(:payments)
  end

  defp order_log(order, payments, locale) do
    order
    |> Ash.load!(:paper_trail_versions, authorize?: false)
    |> Map.fetch!(:paper_trail_versions)
    |> OrderLog.entries(payments, locale)
  end

  defp line_label(%{variant_size: nil} = line_item), do: "#{line_item.quantity} × #{line_item.product_name}"

  defp line_label(line_item),
    do: "#{line_item.quantity} × #{line_item.product_name}, #{variant_size_label(line_item.variant_size)}"

  defp paid_through_stripe?(payments), do: Enum.any?(payments, & &1.payment_intent_id)

  defp reload(order, socket), do: Orders.get_order_for_admin!(order.id, actor: socket.assigns.current_user)

  defp payment_label(%{reverses_payment_id: reversed, method: method}) when is_binary(reversed),
    do: ~t"Undone · #{how = OrderLog.payment_method_label(method)}"

  defp payment_label(%{amount: amount, method: method}) do
    if Decimal.negative?(amount),
      do: ~t"Refund · #{how = OrderLog.payment_method_label(method)}",
      else: OrderLog.payment_method_label(method)
  end

  attr :queue, :map, required: true
  attr :fulfilled, :boolean, required: true

  defp queue_nav(assigns) do
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

  defp queue_link(%{to: nil} = assigns) do
    ~H"""
    <span class="text-base-content/25 flex w-9 items-center justify-center pointer-coarse:w-11" aria-hidden="true">
      <.icon name={@icon} class="h-4 w-4" />
    </span>
    """
  end

  defp queue_link(assigns) do
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
  defp readonly_line_items(assigns) do
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

  defp message_links(assigns) do
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

  defp relative_date_badge(%{tone: :upcoming} = assigns) do
    ~H"""
    <span class="text-base-content/75 block text-sm font-normal">{@label}</span>
    """
  end

  defp relative_date_badge(assigns) do
    ~H"""
    <.badge tone={relative_date_badge_tone(@tone)} class="ml-1.5 align-middle">{@label}</.badge>
    """
  end

  attr :position, :any, required: true
  attr :token, :string, default: nil
  attr :address, :string, default: nil
  attr :distance_km, :any, default: nil

  defp delivery_location(assigns) do
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
  defp payment_row(assigns) do
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
  defp payment_link_buttons(assigns) do
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

  defp payment_link(assigns) do
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
  defp order_menu(assigns) do
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
      <%= if @order.fulfillment_status != :cancelled and @order.fulfillment_method == :delivery do %>
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
  defp unavailable_menu_item(assigns) do
    ~H"""
    <li class="menu-disabled">
      <span aria-disabled="true" class="flex flex-col items-start gap-0.5">
        {render_slot(@inner_block)}
        <span class="text-xs">{@reason}</span>
      </span>
    </li>
    """
  end

  defp email_details_unavailable(order) do
    cond do
      order.fulfillment_status == :cancelled ->
        ~t"The order is cancelled"

      no_email(order) ->
        no_email(order)

      true ->
        nil
    end
  end

  defp confirmation_unavailable(%{fulfillment_status: :fulfilled} = order), do: no_email(order)
  defp confirmation_unavailable(_order), do: ~t"Not fulfilled yet"

  defp receipt_unavailable(%{receipt_available?: true}), do: nil
  defp receipt_unavailable(%{payment_status: :refunded}), do: ~t"The order was refunded"
  defp receipt_unavailable(_order), do: ~t"Not paid"

  # Says when it last went out, so a resend nobody needed is caught before it's sent.
  defp send_email(:order_details, order, message, actor) do
    case Orders.send_order_details_email(order, %{message: message}, actor: actor) do
      {:ok, _order} ->
        {:info, ~t"Order details sent."}

      {:error, error} ->
        Logger.error("Order details for order #{order.id} not sent: #{inspect(error)}")
        {:error, ~t"Could not send the email. Try again in a moment."}
    end
  end

  defp send_email(:receipt, order, message, actor) do
    case Orders.email_receipt(order, %{message: message}, actor: actor) do
      {:ok, _order} ->
        {:info, ~t"Receipt sent."}

      {:error, error} ->
        Logger.error("Receipt for order #{order.id} not sent: #{inspect(error)}")
        {:error, ~t"Could not send the receipt. Try again in a moment."}
    end
  end

  defp send_email(:fulfillment, order, message, actor) do
    case Orders.email_fulfillment_confirmation(order, %{message: message}, actor: actor) do
      {:ok, _order} ->
        {:info, ~t"Confirmation queued."}

      {:error, error} ->
        Logger.error("Fulfillment confirmation for order #{order.id} not queued: #{inspect(error)}")
        {:error, ~t"Could not queue the confirmation."}
    end
  end

  defp send_email(:payment_reminder, order, message, actor) do
    case Orders.send_payment_reminder(order, %{message: message}, actor: actor) do
      {:ok, _order} ->
        {:info, ~t"Payment reminder sent."}

      {:error, error} ->
        Logger.error("Payment reminder for order #{order.id} not sent: #{inspect(error)}")
        {:error, ~t"Could not send the email. Try again in a moment."}
    end
  end

  # The refund forms fill themselves in from what's owed back, so an empty
  # amount reads as that until Jennie changes it.
  defp assign_preview(socket, kind, params) do
    order = socket.assigns.order
    owed_back = order.balance |> Decimal.negate() |> Decimal.max(0) |> Decimal.to_string(:normal)

    inputs = %{
      message: params["message"] || params["note"],
      refund: params["refund"] || params["amount"] || owed_back,
      amount: if(kind == :payment, do: params["amount"] || Decimal.to_string(order.balance, :normal)),
      payment_method: String.to_existing_atom(params["how"] || default_refund_method(order))
    }

    locale = if params["in_swedish"] == "true", do: "sv-FI"
    # Recording a payment emails the same receipt as the menu, for the amount entered.
    kind = if kind == :payment, do: :receipt, else: kind
    assign(socket, :preview, Preview.build(kind, order, inputs, locale))
  end

  defp assign_fulfillment_preview(socket, params) do
    order = socket.assigns.order
    photo? = params["customer_home"] == "false"
    locale = if params["in_swedish"] == "true", do: "sv-FI"
    preview = Preview.build(:fulfillment, order, %{message: params["message"], photo?: photo?}, locale)
    assign(socket, :preview, preview)
  end

  defp default_refund_method(order), do: if(Decimal.positive?(order.paid_through_stripe), do: "stripe", else: "zettle")

  defp swedish_toggle?(order), do: order.locale != "sv-FI"

  defp email_drawer_text(nil, _order, _locale), do: %{}

  defp email_drawer_text(kind, order, locale) do
    {title, submit_label, last_sent_at} =
      case kind do
        :order_details -> {~t"Email order details", ~t"Send order details", order.order_details_emailed_at}
        :receipt -> {~t"Email receipt", ~t"Send receipt", order.receipt_emailed_at}
        :fulfillment -> {~t"Email confirmation", ~t"Send confirmation", order.fulfillment_emailed_at}
        :payment_reminder -> {~t"Send payment reminder", ~t"Send reminder", nil}
      end

    %{
      title: title,
      submit_label: submit_label,
      to: order.customer_email,
      last_sent: last_sent_at && Format.datetime(last_sent_at, locale)
    }
  end

  defp no_email(%{customer_email: nil}), do: ~t"No email address"
  defp no_email(_order), do: nil

  defp cancel_unavailable(%{cancellable?: true}), do: nil
  defp cancel_unavailable(%{fulfillment_status: :fulfilled}), do: ~t"Already fulfilled"
  defp cancel_unavailable(%{fulfillment_status: :cancelled}), do: ~t"Already cancelled"

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

  # The queue was counted at mount with this order still in it.
  defp remaining_to_fulfil(queue), do: queue.total - 1

  defp arrow_symbol("ArrowLeft"), do: "←"
  defp arrow_symbol("ArrowRight"), do: "→"

  # The phone number is the recipient's only on gift deliveries; the buyer collects pickups.
  defp customer_phone?(order), do: !order.gift or order.fulfillment_method == :pickup

  defp pickup_message_urls(%{fulfillment_method: :pickup, fulfillment_status: :pending} = order) do
    message_urls(order.recipient_phone_number, pickup_message(order))
  end

  defp pickup_message_urls(_order), do: nil

  defp payment_message_urls(order) do
    if order.payment_link_open?,
      do: message_urls(customer_phone_number(order), payment_message(order)),
      else: nil
  end

  defp customer_phone_number(order) do
    cond do
      present?(order.customer_phone_number) -> order.customer_phone_number
      customer_phone?(order) -> order.recipient_phone_number
      true -> nil
    end
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
  defp pickup_message(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      ~t"Hi #{order.customer_first_name}, your Eden Flowers order #{order.order_reference} is ready for pick up."
    end)
  end

  defp payment_message(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      amount = Format.currency(order.balance, order.locale)
      url = EdenflowersWeb.PaymentLink.url_for(order)

      ~t"Hi #{order.customer_first_name}, you can pay #{amount} for your Eden Flowers order #{order.order_reference} here: #{url}"
    end)
  end

  defp positive?(nil), do: false
  defp positive?(value), do: Decimal.compare(value, 0) == :gt

  defp negate(nil), do: nil
  defp negate(value), do: Decimal.mult(value, -1)

  defp discount_label(%{promotion_code: code}) when is_binary(code) and code != "", do: ~t"Discount (#{code})"
  defp discount_label(%{promotion_name: name}) when is_binary(name) and name != "", do: ~t"Discount (#{name})"
  defp discount_label(_order), do: ~t"Discount"

  # A fulfilled order is historical, so we skip relative framing there.
  defp fulfillment_relative(date, locale, status) when not is_nil(date) and status != :fulfilled do
    today = Edenflowers.ShopTime.today()

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
    case Date.compare(date, Edenflowers.ShopTime.today()) do
      :lt -> :overdue
      :eq -> :today
      :gt -> :upcoming
    end
  end

  defp relative_date_badge_tone(:overdue), do: :error
  defp relative_date_badge_tone(:today), do: :success

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
      "#{marker}/#{center}/1000x280@2x" <>
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
end

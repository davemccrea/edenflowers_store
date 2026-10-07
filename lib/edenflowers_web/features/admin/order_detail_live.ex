defmodule EdenflowersWeb.Admin.OrderDetailLive do
  use EdenflowersWeb, :live_view

  require Logger

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Order.PaymentMethod
  alias EdenflowersWeb.Admin.OrderLog
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
         |> push_navigate(to: ~p"/admin/orders")}
    end
  end

  defp assign_order(socket, order) do
    payments = payments(order)

    socket
    |> assign(:order, order)
    |> assign(:pickup_message_urls, pickup_message_urls(order))
    |> assign(:payment_message_urls, payment_message_urls(order))
    |> assign(:note_form, to_form(%{"florist_note" => order.florist_note}, as: :note))
    |> assign(:in_person_form, in_person_form(order))
    |> assign(:payments, payments)
    |> assign(:log, order_log(order, payments, socket.assigns.locale))
  end

  defp in_person_form(order) do
    to_form(%{"payment_method" => "zettle", "amount" => Decimal.to_string(order.balance, :normal)}, as: :in_person)
  end

  defp payments(order) do
    order
    |> Ash.load!([payments: Ash.Query.sort(Edenflowers.Orders.Payment, paid_at: :asc)], authorize?: false)
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

  defp owes_money?(order), do: order.fulfillment_status != :cancelled and not Decimal.eq?(order.balance, 0)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="wide">
        <.admin_page_header
          title={@order.customer_name || @order.order_reference}
          back={~p"/admin/orders"}
          back_label={~t"Orders"}
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
                <.gift_badge :if={@order.gift} order={@order} />
                <%!-- The payment card sits below the job on narrow screens; this says money is waiting there. --%>
                <a
                  :if={owes_money?(@order)}
                  href="#order-payment-summary"
                  class="badge badge-sm admin-badge-warning inline-flex items-center gap-1 whitespace-nowrap tabular-nums xl:hidden"
                >
                  {if Decimal.positive?(@order.balance),
                    do: ~t"To collect #{amount = Format.currency(@order.balance, @locale)}",
                    else: ~t"To refund #{amount = Format.currency(Decimal.abs(@order.balance), @locale)}"}
                  <.icon name="hero-arrow-down" class="h-3 w-3" />
                </a>
              </span>
            </span>
          </:subtitle>
          <:actions>
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
            >
              {~t"Mark as fulfilled"}
            </.button>
            <.button
              :if={@order.fulfillment_status == :pending}
              navigate={~p"/admin/orders/#{@order.id}/edit"}
              variant="ghost"
              size="sm"
            >
              <.icon name="hero-pencil-square" class="h-4 w-4" /> {~t"Edit"}
            </.button>
            <.order_menu order={@order} payments={@payments} locale={@locale} />
          </:actions>
        </.admin_page_header>

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
                <.summary_fact label={~t"Method"}>
                  <.fulfillment_method
                    method={@order.fulfillment_method}
                    label={present?(@order.fulfillment_option_name) && @order.fulfillment_option_name}
                    class="whitespace-normal"
                  />
                </.summary_fact>
                <.summary_fact :if={delivery_address?(@order)} label={~t"Deliver to"}>
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
            </.widget>

            <.widget id="order-items" title={~t"To make"}>
              <.readonly_line_items line_items={@order.line_items} />
            </.widget>

            <.widget :if={present?(@order.card_message)} id="order-card" title={~t"Card to write"}>
              <blockquote
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
                  placeholder={~t"Only you see this: what was agreed, timings, anything to remember."}
                />
                <.button type="submit" variant="neutral" size="sm">{~t"Save note"}</.button>
              </.form>
            </.widget>

            <%!-- Last in the job: only needed once the flowers are leaving the shop. --%>
            <.delivery_map
              :if={@order.fulfillment_method == :delivery}
              position={parse_position(@order.position)}
              token={@mapbox_token}
              address={@order.delivery_address}
            />
          </div>

          <%!-- Payment comes first beside the job, but after the contacts once stacked,
               since the badge in the header already points down to it. --%>
          <aside class="flex flex-col gap-6">
            <section
              id="order-payment-summary"
              class={["border p-4 sm:p-5 xl:order-first", if(owes_money?(@order),
    do: "bg-warning/10 border-warning/40",
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
                <div :if={@payments != []} id="order-payments" class="border-base-content/12 mt-1.5 border-t pt-2">
                  <.payment_row :for={payment <- @payments} payment={payment} locale={@locale} />
                </div>
              </dl>

              <.collect
                :if={owes_money?(@order)}
                order={@order}
                payments={@payments}
                in_person_form={@in_person_form}
                payment_message_urls={@payment_message_urls}
                locale={@locale}
              />
            </section>

            <.widget id="order-customer" title={~t"Customer"}>
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
                    class="link link-primary inline-flex items-center gap-1.5"
                  >
                    <.icon name="hero-user" class="h-3.5 w-3.5 shrink-0" />
                    {~t"View customer's orders"}
                  </.link>
                </:contact>
              </.person_block>
            </.widget>

            <.widget
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
            </.widget>

            <.widget id="order-log" title={~t"History"}>
              <ol class="divide-base-content/8 divide-y text-sm">
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
                        <dt :if={label} class="text-base-content/65 text-xs">{label}</dt>
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
    amount = String.replace(params["amount"], ",", ".")

    case Orders.record_in_person_payment(socket.assigns.order, amount, params["payment_method"],
           actor: socket.assigns.current_user
         ) do
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

  # The order details email carries the link, so sending it is opening one.
  def handle_event("email_payment_link", _params, socket) do
    actor = socket.assigns.current_user

    with {:ok, order} <- Orders.open_payment_link(socket.assigns.order, actor: actor),
         {:ok, order} <- Orders.send_order_details_email(order, actor: actor) do
      {:noreply, socket |> assign_order(reload(order, socket)) |> put_flash(:info, ~t"Payment link emailed.")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, ~t"Could not email the payment link.")}
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

  def handle_event("refund_with_stripe", _params, socket) do
    case Edenflowers.Payments.refund_balance(socket.assigns.order) do
      {:ok, refunds} ->
        message =
          cond do
            refunds == [] -> ~t"Nothing left to refund. Stripe already has refunds covering it."
            Enum.all?(refunds, &(&1.status == "succeeded")) -> ~t"Refunded through Stripe."
            true -> ~t"Refund sent to Stripe. It shows here once it goes through."
          end

        {:noreply, socket |> assign_order(reload(socket.assigns.order, socket)) |> put_flash(:info, message)}

      {:error, reason} ->
        Logger.error("Stripe refund for order #{socket.assigns.order.id} failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, ~t"Could not refund through Stripe. Check the payment in Stripe.")}
    end
  end

  defp reload(order, socket), do: Orders.get_order_for_admin!(order.id, actor: socket.assigns.current_user)

  defp cancel_confirmation(%{holds_money?: true}),
    do: ~t"Cancel this order? It is paid, so refund the customer in Stripe or by hand. This can't be undone."

  defp cancel_confirmation(_order), do: ~t"Cancel this order? This can't be undone."

  defp in_person_method_options do
    Enum.map(PaymentMethod.in_person(), &{OrderLog.payment_method_label(&1), &1})
  end

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

  attr :line_items, :list, required: true

  # What to make, not what it costs: the prices are in the Payment section.
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
  attr :sms_label, :string, required: true
  attr :whatsapp_label, :string, required: true

  defp message_links(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-x-4 gap-y-1.5">
      <a href={@urls.sms} class="link link-primary inline-flex items-center gap-1.5">
        <.icon name="hero-chat-bubble-left-ellipsis" class="h-3.5 w-3.5 shrink-0" />
        {@sms_label}
      </a>
      <a
        href={@urls.whatsapp}
        target="_blank"
        rel="noopener"
        class="link link-primary inline-flex items-center gap-1.5"
      >
        <.icon name="hero-chat-bubble-oval-left" class="h-3.5 w-3.5 shrink-0" />
        {@whatsapp_label}
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
    <div :if={@directions} id="order-directions" class="border-base-content/12 overflow-hidden border">
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
          class="block h-48 w-full object-cover"
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
  attr :ruled, :boolean, default: false, doc: "starts a new group under the rows above"

  defp money_row(assigns) do
    ~H"""
    <div class={["flex items-center justify-between gap-4 py-0.5", @ruled && "border-base-content/12 mt-1.5 border-t pt-2", @strong && "border-base-content/12 text-base-content mt-1.5 border-t pt-3 font-semibold", @muted && "text-base-content/65"]}>
      <dt class={money_row_tone(@strong, @muted, "text-base-content/75")}>
        {@label}
      </dt>
      <dd class={["tabular-nums", money_row_tone(@strong, @muted, "text-base-content/90")]}>
        {Format.currency(@amount, @locale)}
      </dd>
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
          {@payment.paid_at |> DateTime.shift_zone!("Europe/Helsinki") |> DateTime.to_date() |> Format.day_month(@locale)}
        </time>
        <a
          :if={@payment.payment_intent_id}
          href={StripeAPI.dashboard_payment_url(@payment.payment_intent_id)}
          target="_blank"
          rel="noopener"
          class="text-base-content/60 -my-3 -ml-1 inline-flex p-2 align-middle hover:text-base-content"
          aria-label={~t"View #{amount = Format.currency(@payment.amount, @locale)} payment in Stripe"}
        >
          <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
        </a>
      </dt>
      <dd class="text-base-content/90 tabular-nums">
        {Format.currency(negate(@payment.amount), @locale)}
      </dd>
    </div>
    """
  end

  attr :order, :map, required: true
  attr :payments, :list, required: true
  attr :in_person_form, :any, required: true
  attr :payment_message_urls, :map, default: nil
  attr :locale, :string, required: true

  # In the order Jennie reaches for it: send the link, or record what she took herself.
  defp collect(assigns) do
    ~H"""
    <div id="order-collect" class="border-warning/40 mt-4 border-t pt-4">
      <p class="text-base-content flex items-baseline justify-between gap-4 text-base font-semibold">
        {if Decimal.positive?(@order.balance), do: ~t"To collect", else: ~t"To refund"}
        <span class="tabular-nums">{Format.currency(Decimal.abs(@order.balance), @locale)}</span>
      </p>

      <div class="mt-3 flex flex-wrap items-center gap-2">
        <.button
          :if={Decimal.positive?(@order.balance) && @order.customer_email}
          type="button"
          phx-click="email_payment_link"
          data-confirm={
            confirm_send(
              ~t"Email a payment link to #{email = @order.customer_email}?",
              @order.payment_link_open? && @order.details_emailed_at,
              @locale
            )
          }
          variant="primary"
          size="sm"
        >
          <.icon name="hero-envelope" class="h-4 w-4" />
          {if @order.payment_link_open? && @order.details_emailed_at,
            do: ~t"Resend payment link",
            else: ~t"Email payment link"}
        </.button>
        <.button
          :if={Decimal.positive?(@order.balance) && !@order.payment_link_open?}
          type="button"
          phx-click="open_payment_link"
          variant="ghost"
          size="sm"
        >
          {~t"Create payment link"}
        </.button>
        <.button
          :if={Decimal.negative?(@order.balance) && paid_through_stripe?(@payments)}
          type="button"
          phx-click="refund_with_stripe"
          phx-disable-with={~t"Refunding…"}
          data-confirm={
            ~t"Refund #{amount = Format.currency(Decimal.abs(@order.balance), @locale)} to the customer's card through Stripe?"
          }
          variant="primary"
          size="sm"
        >
          {~t"Refund with Stripe"}
        </.button>
      </div>

      <div :if={@order.payment_link_open?} id="order-payment-link" class="mt-4">
        <label for="payment-link-url" class="eyebrow text-base-content/65 mb-1.5 block">
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
          <button
            id="copy-payment-link"
            type="button"
            phx-click={JS.dispatch("edenflowers:copy", to: "#payment-link-url", detail: %{trigger: "#copy-payment-link"})}
            class="btn btn-ghost btn-sm btn-square group"
            title={~t"Copy payment link"}
            aria-label={~t"Copy payment link"}
          >
            <.icon name="hero-clipboard" class="h-4 w-4 group-data-copied:hidden" />
            <.icon name="hero-check" class="text-success hidden h-4 w-4 group-data-copied:inline-block" />
            <span class="sr-only" aria-live="polite">
              <span class="hidden group-data-copied:inline">{~t"Copied"}</span>
            </span>
          </button>
        </div>
        <div :if={@payment_message_urls} class="mt-2.5 text-sm">
          <.message_links
            urls={@payment_message_urls}
            sms_label={~t"Text payment link"}
            whatsapp_label={~t"WhatsApp payment link"}
          />
        </div>
      </div>

      <details id="in-person-payment" phx-mounted={JS.ignore_attributes(["open"])} class="group mt-4">
        <summary class="text-base-content flex cursor-pointer list-none items-center gap-1 text-sm font-medium">
          {if Decimal.positive?(@order.balance),
            do: ~t"Record payment taken in person",
            else: ~t"Record refund given in person"}
          <.icon
            name="hero-chevron-right"
            class="text-base-content/50 h-3.5 w-3.5 transition-transform group-open:rotate-90"
          />
        </summary>
        <.form for={@in_person_form} id="in-person-payment-form" phx-submit="record_in_person_payment" class="mt-3">
          <fieldset aria-describedby="in-person-payment-help">
            <div class="grid grid-cols-2 items-end gap-2 text-sm">
              <.input
                field={@in_person_form[:payment_method]}
                type="select"
                label={~t"How"}
                class="select select-sm w-full"
                options={in_person_method_options()}
              />
              <.input
                field={@in_person_form[:amount]}
                type="text"
                inputmode="decimal"
                label={~t"Amount (€)"}
                class="input input-sm w-full tabular-nums"
              />
              <.button
                type="submit"
                variant="primary"
                size="sm"
                class="col-span-2"
                data-confirm={~t"Record this payment? It can't be removed, only offset by recording the opposite amount."}
              >
                {~t"Record payment"}
              </.button>
            </div>
            <p id="in-person-payment-help" class="text-base-content/65 mt-1.5 text-xs">
              {~t"A minus amount records a refund. To correct a mistake, record the opposite amount."}
            </p>
          </fieldset>
        </.form>
      </details>
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
      |> assign(:paid?, assigns.order.payment_status == :paid)
      |> assign(:email_details_unavailable, email_details_unavailable(assigns.order))
      |> assign(:no_email, no_email(assigns.order))
      |> assign(:receipt_unavailable, receipt_unavailable(assigns.order))
      |> assign(:paid_through_stripe?, paid_through_stripe?(assigns.payments))
      |> assign(:cancel_unavailable, cancel_unavailable(assigns.order))

    ~H"""
    <div class="dropdown dropdown-end">
      <button type="button" tabindex="0" class="btn btn-ghost btn-sm btn-square" aria-label={~t"More actions"}>
        <.icon name="hero-ellipsis-horizontal" class="h-5 w-5" />
      </button>
      <ul tabindex="0" class="dropdown-content menu bg-base-100 border-base-300 z-10 mt-2 w-56 border p-1 shadow">
        <%!-- One email at a time: the details carry how to pay, so once paid the receipt replaces them. --%>
        <%= if @paid? do %>
          <li :if={!@no_email}>
            <button
              type="button"
              phx-click="email_receipt"
              data-confirm={
                confirm_send(
                  ~t"Email the receipt to #{email = @order.customer_email}?",
                  @order.receipt_emailed_at,
                  @locale
                )
              }
            >
              {if @order.receipt_emailed_at, do: ~t"Resend receipt", else: ~t"Email receipt"}
            </button>
          </li>
          <.unavailable_menu_item :if={@no_email} reason={@no_email}>
            {~t"Email receipt"}
          </.unavailable_menu_item>
        <% else %>
          <li :if={!@email_details_unavailable}>
            <button
              type="button"
              phx-click="send_order_details"
              data-confirm={
                confirm_send(
                  ~t"Email the order details to #{email = @order.customer_email}?",
                  @order.details_emailed_at,
                  @locale
                )
              }
            >
              {if @order.details_emailed_at, do: ~t"Resend order details", else: ~t"Email order details"}
            </button>
          </li>
          <.unavailable_menu_item :if={@email_details_unavailable} reason={@email_details_unavailable}>
            {~t"Email order details"}
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

        <%!-- Refunds arrive by webhook; this catches one that never did. --%>
        <li :if={@paid_through_stripe?}>
          <button type="button" phx-click="fetch_stripe_refunds">
            {~t"Fetch refunds from Stripe"}
          </button>
        </li>

        <li :if={!@cancel_unavailable}>
          <button type="button" phx-click="cancel_order" data-confirm={cancel_confirmation(@order)} class="text-error">
            {~t"Cancel order"}
          </button>
        </li>
        <.unavailable_menu_item :if={@cancel_unavailable} reason={@cancel_unavailable}>
          {~t"Cancel order"}
        </.unavailable_menu_item>
      </ul>
    </div>
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
      order.fulfillment_status == :cancelled -> ~t"The order is cancelled"
      true -> no_email(order)
    end
  end

  defp receipt_unavailable(%{payment_status: :paid}), do: nil
  defp receipt_unavailable(%{payment_status: :refunded}), do: ~t"The order was refunded"
  defp receipt_unavailable(_order), do: ~t"Not paid"

  # Says when it last went out, so a resend nobody needed is caught before it's sent.
  defp confirm_send(question, last_sent_at, _locale) when last_sent_at in [nil, false], do: question

  defp confirm_send(question, last_sent_at, locale) do
    ~t"Last sent #{time = Format.datetime(last_sent_at, locale)}." <> " " <> question
  end

  defp no_email(%{customer_email: nil}), do: ~t"No email address"
  defp no_email(_order), do: nil

  defp cancel_unavailable(%{fulfillment_status: :pending}), do: nil
  defp cancel_unavailable(%{fulfillment_status: :fulfilled}), do: ~t"Already fulfilled"
  defp cancel_unavailable(%{fulfillment_status: :cancelled}), do: ~t"Already cancelled"

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

  defp delivery_address?(order), do: order.fulfillment_method == :delivery && present?(order.delivery_address)

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

  defp fastmail_search_url(email) do
    "https://app.fastmail.com/mail/search:#{URI.encode_www_form(email)}"
  end
end

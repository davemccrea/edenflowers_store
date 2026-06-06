defmodule EdenflowersWeb.Admin.OrderDetailLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Store.Order
  alias Edenflowers.StripeAPI
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Order.get_for_admin(id, actor: socket.assigns.current_user) do
      {:ok, %Order{} = order} ->
        {:ok,
         socket
         |> assign(:page_title, ~t"Order #{order.order_reference}")
         |> assign(:locale, Localize.get_locale())
         |> assign(:order, order)}

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
      <.admin_page width="wide">
        <.admin_page_header
          title={@order.customer_name || ~t"Order"}
          back={~p"/admin/orders"}
          back_label={~t"Orders"}
        >
          <:subtitle>
            <span>{@order.order_reference}</span>
            <span :if={@order.ordered_at} aria-hidden="true">·</span>
            <span :if={@order.ordered_at}>{~t"Ordered"} {Format.datetime(@order.ordered_at, @locale)}</span>
          </:subtitle>
          <:actions>
            <div class="flex items-center gap-1.5">
              <span class="text-base-content/55 text-xs">{~t"Payment"}</span>
              <.payment_status_badge status={@order.payment_status} />
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-base-content/55 text-xs">{~t"Fulfillment"}</span>
              <.fulfillment_status_badge status={@order.fulfillment_status} />
            </div>
          </:actions>
        </.admin_page_header>

        <section
          id="order-fulfillment-summary"
          class="bg-base-100 border-base-300/70 mb-8 rounded-lg border p-4 sm:mb-10 sm:p-6"
        >
          <div class="mb-5 flex items-center justify-between gap-4">
            <h2 class="text-base-content text-base font-semibold">{~t"Fulfillment"}</h2>
            <button
              :if={@order.fulfillment_status == :pending}
              type="button"
              phx-click="mark_fulfilled"
              data-confirm={~t"Mark this order as fulfilled? This action is irreversible and cannot be undone."}
              class="btn btn-primary btn-sm"
            >
              {~t"Mark as fulfilled"}
            </button>
          </div>
          <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-[1.1fr_1fr_1.6fr]">
            <div>
              <p class="eyebrow text-base-content/65 mb-1.5">{~t"Fulfillment date"}</p>
              <p class="text-base-content text-base font-semibold">
                {Format.date(@order.fulfillment_date, @locale)}
              </p>
            </div>
            <.summary_fact label={~t"Method"}>
              <span class="inline-flex items-center gap-2">
                <.icon name={fulfillment_icon(@order.fulfillment_method)} class="text-base-content/60 h-4 w-4" />
                {fulfillment_description(@order)}
              </span>
            </.summary_fact>
            <.summary_fact
              :if={@order.fulfillment_method == :delivery && present?(@order.delivery_address)}
              label={~t"Destination"}
            >
              {@order.delivery_address}
            </.summary_fact>
            <.summary_fact :if={present?(@order.recipient_name)} label={~t"Recipient"}>
              <span>
                {@order.recipient_name}
                <span :if={@order.gift} class="badge badge-soft badge-sm badge-neutral ml-1.5">{~t"Gift"}</span>
              </span>
            </.summary_fact>
            <.summary_fact :if={present?(@order.recipient_phone_number)} label={~t"Phone"}>
              <a href={"tel:#{@order.recipient_phone_number}"} class="link link-primary">
                {@order.recipient_phone_number}
              </a>
            </.summary_fact>
            <.summary_fact :if={present?(@order.delivery_instructions)} label={~t"Instructions"}>
              {@order.delivery_instructions}
            </.summary_fact>
            <.summary_fact :if={@order.distance_km} label={~t"Distance"}>
              {@order.distance_km} km
            </.summary_fact>
          </div>
        </section>

        <div class="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <main class="space-y-8">
            <.detail_section title={~t"Line items"}>
              <.readonly_line_items line_items={@order.line_items} locale={@locale} />
            </.detail_section>

            <.detail_section :if={present?(@order.card_message)} title={~t"Card message"}>
              <figure class="border-base-300/70 bg-base-200/40 rounded-md border p-4">
                <blockquote class="text-base-content whitespace-pre-wrap break-words text-sm">
                  {@order.card_message}
                </blockquote>
              </figure>
            </.detail_section>
          </main>

          <aside class="space-y-6">
            <section id="order-payment-summary" class="bg-base-100 border-base-300/70 rounded-lg border p-4">
              <p class="eyebrow text-base-content/65 mb-1">{~t"Grand total"}</p>
              <p class="text-base-content mb-4 text-3xl font-semibold tabular-nums tracking-tight">
                {money(@order.grand_total, @locale)}
              </p>
              <dl class="text-sm">
                <.money_row label={~t"Items subtotal"} amount={@order.items_subtotal} locale={@locale} />
                <.money_row
                  :if={positive?(@order.discount)}
                  label={discount_label(@order)}
                  amount={negate(@order.discount)}
                  locale={@locale}
                />
                <.money_row label={~t"Fulfillment fee"} amount={@order.fulfillment_fee} locale={@locale} />
                <.money_row label={~t"VAT"} amount={@order.tax} locale={@locale} />
              </dl>
              <a
                :if={@order.payment_intent_id}
                href={StripeAPI.dashboard_payment_url(@order.payment_intent_id)}
                target="_blank"
                rel="noopener"
                class="btn btn-outline btn-sm mt-4 w-full"
              >
                {~t"View payment in Stripe"}
                <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
              </a>
            </section>

            <section>
              <h2 class="text-base-content mb-3 text-base font-semibold">{~t"Customer"}</h2>
              <dl class="space-y-3 text-sm">
                <div :if={present?(@order.customer_name)}>
                  <dt class="text-base-content/55">{~t"Name"}</dt>
                  <dd class="text-base-content">{@order.customer_name}</dd>
                </div>
                <div :if={@order.customer_email}>
                  <dt class="text-base-content/55">{~t"Email"}</dt>
                  <dd class="text-base-content mt-0.5 break-words">
                    <a href={"mailto:#{@order.customer_email}"} class="link link-primary">
                      {@order.customer_email}
                    </a>
                  </dd>
                </div>
              </dl>
            </section>
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("mark_fulfilled", _params, socket) do
    case Order.mark_fulfilled(socket.assigns.order, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:noreply,
         socket
         |> assign(:order, order)
         |> put_flash(:info, ~t"Order marked as fulfilled.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not mark order as fulfilled.")}
    end
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp detail_section(assigns) do
    ~H"""
    <section>
      <h2 class="text-base-content mb-3 text-base font-semibold">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :line_items, :list, required: true
  attr :locale, :string, required: true

  defp readonly_line_items(assigns) do
    ~H"""
    <ul class="divide-base-300/70 divide-y">
      <li :for={line_item <- @line_items} class="flex gap-4 py-4 first:pt-0 last:pb-0">
        <.image
          src={line_item.product_image_slug}
          alt={"Image of #{line_item.product_name}"}
          width={64}
          height={64}
          sizes="64px"
          class="h-16 w-16 shrink-0 rounded-md object-cover"
        />
        <div class="min-w-0 flex-1">
          <div class="flex gap-3">
            <div class="min-w-0 flex-1">
              <p class="text-base-content truncate text-sm font-medium">{line_item.product_name}</p>
              <p :if={line_item.variant_size} class="text-base-content/60 mt-0.5 text-xs capitalize">
                {line_item.variant_size}
              </p>
              <p class="text-base-content/60 mt-1 text-xs tabular-nums">× {line_item.quantity}</p>
            </div>
            <p class="text-base-content text-sm tabular-nums">{money(line_item.subtotal, @locale)}</p>
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
      <div class="text-base-content text-sm font-medium leading-relaxed">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :amount, :any, default: nil
  attr :locale, :string, required: true
  attr :strong, :boolean, default: false

  defp money_row(assigns) do
    ~H"""
    <div class={["flex items-center justify-between gap-4 py-1.5", @strong && "border-base-300/70 mt-1.5 border-t pt-3 font-semibold"]}>
      <dt class="text-base-content/65">{@label}</dt>
      <dd class="text-base-content tabular-nums">{money(@amount, @locale)}</dd>
    </div>
    """
  end

  defp money(amount, locale), do: Format.currency(amount || 0, locale)

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

  defp fulfillment_label(:delivery), do: ~t"Delivery"
  defp fulfillment_label(:pickup), do: ~t"Pickup"
  defp fulfillment_label(_), do: nil

  defp fulfillment_icon(:delivery), do: "hero-truck"
  defp fulfillment_icon(:pickup), do: "hero-building-storefront"
  defp fulfillment_icon(_), do: "hero-question-mark-circle"

  defp fulfillment_description(order) do
    [fulfillment_label(order.fulfillment_method), order.fulfillment_option_name]
    |> Enum.reject(&(not present?(&1)))
    |> Enum.join(" · ")
  end
end

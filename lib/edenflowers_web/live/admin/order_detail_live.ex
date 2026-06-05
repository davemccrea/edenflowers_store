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
        <.admin_page_header title={@order.order_reference} back={~p"/admin/orders"} back_label={~t"Orders"}>
          <:actions>
            <span
              :if={@order.fulfillment_status == :fulfilled}
              class="badge badge-soft badge-sm badge-success gap-1"
            >
              <.icon name="hero-check" class="h-3 w-3" /> {~t"Fulfilled"}
            </span>
            <button
              :if={@order.fulfillment_status == :pending}
              type="button"
              phx-click="mark_fulfilled"
              data-confirm={~t"Mark this order as fulfilled? This action is irreversible and cannot be undone."}
              class="btn btn-primary btn-sm"
            >
              {~t"Mark as fulfilled"}
            </button>
          </:actions>
        </.admin_page_header>

        <section class="border-base-300/70 mb-8 flex flex-col gap-4 border-b pb-6 sm:mb-10 sm:flex-row sm:items-end sm:justify-between sm:gap-6 sm:pb-8">
          <div class="min-w-0">
            <p class="eyebrow text-base-content/65 mb-1">{~t"Grand total"}</p>
            <p class="text-base-content truncate text-3xl font-semibold tabular-nums tracking-tight sm:text-4xl">
              {money(@order.grand_total, @locale)}
            </p>
          </div>
          <div class="flex flex-wrap gap-2 sm:justify-end">
            <.payment_status_badge status={@order.payment_status} />
            <.fulfillment_status_badge status={@order.fulfillment_status} />
          </div>
        </section>

        <section class="text-base-content/65 mb-10 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
          <span>{~t"Reference"} {@order.order_reference}</span>
          <span :if={@order.ordered_at} aria-hidden="true">·</span>
          <span :if={@order.ordered_at}>{~t"Ordered"} {Format.datetime(@order.ordered_at, @locale)}</span>
          <span :if={@order.locale} aria-hidden="true">·</span>
          <span :if={@order.locale}>{~t"Locale"} {@order.locale}</span>
        </section>

        <div class="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <main class="space-y-8">
            <.detail_section title={~t"Line items"}>
              <.readonly_line_items line_items={@order.line_items} locale={@locale} />
            </.detail_section>

            <.detail_section title={~t"Money"}>
              <dl class="divide-base-300/70 divide-y text-sm">
                <.money_row label={~t"Items subtotal"} amount={@order.items_subtotal} locale={@locale} />
                <.money_row
                  :if={positive?(@order.discount)}
                  label={discount_label(@order)}
                  amount={negate(@order.discount)}
                  locale={@locale}
                />
                <.money_row label={~t"Fulfillment fee"} amount={@order.fulfillment_fee} locale={@locale} />
                <.money_row label={~t"Items VAT"} amount={@order.items_tax} locale={@locale} />
                <.money_row label={~t"Fulfillment VAT"} amount={@order.fulfillment_tax} locale={@locale} />
                <.money_row label={~t"Total VAT"} amount={@order.tax} locale={@locale} />
                <.money_row label={~t"Grand total"} amount={@order.grand_total} locale={@locale} strong />
              </dl>
            </.detail_section>
          </main>

          <aside class="space-y-6">
            <.detail_section title={~t"Customer"}>
              <dl class="space-y-3 text-sm">
                <.fact label={~t"Name"} value={@order.customer_name} />
                <div>
                  <dt class="text-base-content/55">{~t"Email"}</dt>
                  <dd class="text-base-content mt-0.5 break-words">
                    <a :if={@order.customer_email} href={"mailto:#{@order.customer_email}"} class="link link-primary">
                      {@order.customer_email}
                    </a>
                    <span :if={is_nil(@order.customer_email)} class="text-base-content/30" aria-hidden="true">—</span>
                  </dd>
                </div>
              </dl>
            </.detail_section>

            <.detail_section title={~t"Fulfillment"}>
              <dl class="space-y-3 text-sm">
                <.fact label={~t"Method"} value={fulfillment_label(@order.fulfillment_method)} />
                <.fact label={~t"Option"} value={@order.fulfillment_option_name || option_name(@order.fulfillment_option)} />
                <.fact label={~t"Date"} value={Format.date(@order.fulfillment_date, @locale)} />
                <.fact label={~t"Recipient"} value={@order.recipient_name} />
                <.fact label={~t"Phone"} value={@order.recipient_phone_number} />
                <.fact label={~t"Address"} value={@order.delivery_address} />
                <.fact label={~t"Instructions"} value={@order.delivery_instructions} />
                <.fact :if={@order.distance_km} label={~t"Distance"} value={"#{@order.distance_km} km"} />
                <.fact label={~t"Gift"} value={gift_label(@order.gift)} />
                <.fact label={~t"Card message"} value={@order.card_message} />
              </dl>
            </.detail_section>

            <.detail_section title={~t"Payment"}>
              <dl class="space-y-3 text-sm">
                <div>
                  <dt class="text-base-content/55">{~t"Stripe payment"}</dt>
                  <dd class="text-base-content mt-0.5 break-words">
                    <a
                      :if={@order.payment_intent_id}
                      href={StripeAPI.dashboard_payment_url(@order.payment_intent_id)}
                      target="_blank"
                      rel="noopener"
                      class="link link-primary"
                    >
                      {@order.payment_intent_id}
                    </a>
                    <span :if={is_nil(@order.payment_intent_id)} class="text-base-content/30" aria-hidden="true">—</span>
                  </dd>
                </div>
                <div>
                  <dt class="text-base-content/55">{~t"Status"}</dt>
                  <dd class="mt-1"><.payment_status_badge status={@order.payment_status} /></dd>
                </div>
              </dl>
            </.detail_section>

            <.detail_section title={~t"Receipt"}>
              <dl class="space-y-3 text-sm">
                <.fact label={~t"Emailed"} value={datetime_or_dash(@order.receipt_emailed_at, @locale)} />
                <.fact label={~t"SHA-256"} value={@order.receipt_sha256} />
              </dl>
            </.detail_section>
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
  attr :value, :any, default: nil

  defp fact(assigns) do
    ~H"""
    <div>
      <dt class="text-base-content/55">{@label}</dt>
      <dd class="text-base-content mt-0.5 whitespace-pre-wrap break-words">{present(@value)}</dd>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :amount, :any, default: nil
  attr :locale, :string, required: true
  attr :strong, :boolean, default: false

  defp money_row(assigns) do
    ~H"""
    <div class={["flex items-center justify-between gap-4 py-3", @strong && "font-semibold"]}>
      <dt class="text-base-content/65">{@label}</dt>
      <dd class="text-base-content tabular-nums">{money(@amount, @locale)}</dd>
    </div>
    """
  end

  defp money(amount, locale), do: Format.currency(amount || 0, locale)

  defp datetime_or_dash(nil, _locale), do: nil
  defp datetime_or_dash(datetime, locale), do: Format.datetime(datetime, locale)

  defp present(nil), do: Phoenix.HTML.raw(~s|<span class="text-base-content/30" aria-hidden="true">—</span>|)
  defp present(""), do: present(nil)
  defp present(value), do: value

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

  defp option_name(%{name: name}), do: name
  defp option_name(_), do: nil

  defp gift_label(true), do: ~t"Yes"
  defp gift_label(false), do: ~t"No"
  defp gift_label(_), do: nil
end

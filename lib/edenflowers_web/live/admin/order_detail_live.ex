defmodule EdenflowersWeb.Admin.OrderDetailLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Store.Order
  alias Edenflowers.StripeAPI
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  # The shop's address — used as the origin for delivery directions.
  @shop_origin "Muurahaistie 1, 65230 Vaasa"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Order.get_for_admin(id, actor: socket.assigns.current_user) do
      {:ok, %Order{} = order} ->
        {:ok,
         socket
         |> assign(:page_title, ~t"Order #{order.order_reference}")
         |> assign(:locale, Localize.get_locale())
         |> assign(:mapbox_token, Application.get_env(:edenflowers, :mapbox_token))
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
          title={@order.order_reference}
          back={~p"/admin/orders"}
          back_label={~t"Orders"}
        >
          <:subtitle>
            <span class="inline-flex flex-wrap items-center gap-x-2 gap-y-1">
              <span :if={present?(@order.customer_name)}>{@order.customer_name}</span>
              <.gift_badge :if={@order.gift} order={@order} />
              <span :if={@order.ordered_at} aria-hidden="true">·</span>
              <span :if={@order.ordered_at}>{~t"Ordered"} {Format.datetime(@order.ordered_at, @locale)}</span>
            </span>
          </:subtitle>
          <:actions>
            <div class="flex items-center gap-4">
              <div class="flex flex-col items-start gap-1">
                <span class="eyebrow text-base-content/55">{~t"Payment"}</span>
                <.payment_status_badge status={@order.payment_status} />
              </div>
              <div class="flex flex-col items-start gap-1">
                <span class="eyebrow text-base-content/55">{~t"Fulfillment"}</span>
                <.fulfillment_status_badge status={@order.fulfillment_status} />
              </div>
            </div>
          </:actions>
        </.admin_page_header>

        <section
          id="order-fulfillment-summary"
          class="bg-base-100 border-base-300/70 mb-6 rounded-lg border p-4 sm:p-5"
        >
          <div class="mb-5 flex items-center justify-between gap-4">
            <h2 class="text-base-content text-base font-semibold">{~t"Fulfillment"}</h2>
            <button
              :if={@order.fulfillment_status == :pending}
              type="button"
              phx-click="mark_fulfilled"
              data-confirm={~t"Mark this order as fulfilled? This action is irreversible and cannot be undone."}
              class="btn btn-primary btn-sm shrink-0"
            >
              {~t"Mark as fulfilled"}
            </button>
          </div>

          <div class="mb-6">
            <p class="eyebrow text-base-content/65 mb-1">{~t"Date"}</p>
            <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
              <p class="text-base-content text-lg font-semibold">
                {Format.date(@order.fulfillment_date, @locale)}
              </p>
              <.relative_date_badge
                :if={fulfillment_relative(@order.fulfillment_date, @locale, @order.fulfillment_status)}
                label={fulfillment_relative(@order.fulfillment_date, @locale, @order.fulfillment_status)}
              />
            </div>
          </div>

          <div class="grid grid-cols-1 gap-x-6 gap-y-5 sm:grid-cols-2 lg:grid-cols-3">
            <.summary_fact label={~t"Method"}>
              <span class="inline-flex items-center gap-2">
                <span aria-hidden="true" class="leading-none">{fulfillment_emoji(@order.fulfillment_method)}</span>
                {fulfillment_description(@order)}
              </span>
            </.summary_fact>
            <.summary_fact
              :if={@order.fulfillment_method == :delivery && present?(@order.delivery_address)}
              label={~t"Destination"}
            >
              {@order.delivery_address}
            </.summary_fact>
            <.summary_fact :if={present?(@order.delivery_instructions)} label={~t"Instructions"}>
              {@order.delivery_instructions}
            </.summary_fact>
            <.summary_fact :if={@order.distance_km} label={~t"Distance"}>
              {@order.distance_km} km
            </.summary_fact>
          </div>

          <.delivery_map
            :if={@order.fulfillment_method == :delivery}
            position={parse_position(@order.position)}
            token={@mapbox_token}
            address={@order.delivery_address}
          />
        </section>

        <div class="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <main class="space-y-6">
            <.detail_section :if={present?(@order.card_message)} title={~t"Card message"}>
              <blockquote class="border-base-300 text-base-content whitespace-pre-wrap break-words border-l-2 pl-3 text-sm italic">
                {@order.card_message}
              </blockquote>
            </.detail_section>

            <.detail_section title={~t"Line items"}>
              <.readonly_line_items line_items={@order.line_items} locale={@locale} />
            </.detail_section>

            <.detail_section id="order-payment-summary" title={~t"Payment"}>
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
                <.money_row strong label={~t"Total"} amount={@order.grand_total} locale={@locale} />
              </dl>
              <a
                :if={@order.payment_intent_id}
                href={StripeAPI.dashboard_payment_url(@order.payment_intent_id)}
                target="_blank"
                rel="noopener"
                class="btn btn-outline btn-sm mt-5"
              >
                {~t"View payment in Stripe"}
                <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
              </a>
            </.detail_section>
          </main>

          <aside class="space-y-6">
            <.detail_section id="order-customer" title={~t"Customer"}>
              <.person_block name={@order.customer_name}>
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
                <:contact :if={!@order.gift && present?(@order.recipient_phone_number)}>
                  <.phone_link phone_number={@order.recipient_phone_number} />
                </:contact>
              </.person_block>
            </.detail_section>

            <.detail_section
              :if={@order.gift && present?(@order.recipient_name)}
              id="order-recipient"
              title={~t"Recipient"}
            >
              <.person_block name={@order.recipient_name}>
                <:contact :if={present?(@order.recipient_phone_number)}>
                  <.phone_link phone_number={@order.recipient_phone_number} />
                </:contact>
              </.person_block>
            </.detail_section>

            <.detail_section id="order-timeline" title={~t"Timeline"}>
              <ul class="timeline timeline-compact timeline-vertical">
                <.timeline_step label={~t"Order placed"} status={:done} first>
                  {Format.datetime(@order.ordered_at, @locale)}
                </.timeline_step>
                <.timeline_step label={~t"Payment"} status={payment_step_status(@order.payment_status)}>
                  {payment_step_detail(@order.payment_status)}
                </.timeline_step>
                <.timeline_step
                  label={~t"Fulfilled"}
                  status={(@order.fulfillment_status == :fulfilled && :done) || :pending}
                  last
                >
                  <span :if={@order.fulfillment_status != :fulfilled}>{~t"Pending"}</span>
                </.timeline_step>
              </ul>
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

  attr :id, :string, default: nil
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp detail_section(assigns) do
    ~H"""
    <section id={@id} class="bg-base-100 border-base-300/70 rounded-lg border p-4 sm:p-5">
      <h2 class="text-base-content mb-4 text-base font-semibold">{@title}</h2>
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
          alt={~t"Image of #{line_item.product_name}"}
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

  attr :name, :string, default: nil
  slot :contact

  defp person_block(assigns) do
    ~H"""
    <div>
      <p class="text-base-content text-base font-medium">{@name || "—"}</p>
      <div :for={contact <- @contact} class="mt-1.5 text-sm">{render_slot(contact)}</div>
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

  attr :order, :map, required: true

  defp gift_badge(assigns) do
    ~H"""
    <span
      class="badge badge-soft badge-sm badge-neutral inline-flex items-center gap-1 whitespace-nowrap"
      title={(present?(@order.recipient_name) && ~t"Gift for #{@order.recipient_name}") || ~t"Gift order"}
    >
      <span aria-hidden="true">🎁</span>
      <span :if={present?(@order.recipient_name)} class="max-w-[10rem] truncate">{@order.recipient_name}</span>
      <span :if={!present?(@order.recipient_name)}>{~t"Gift"}</span>
    </span>
    """
  end

  attr :label, :string, required: true
  attr :status, :atom, required: true, values: [:done, :pending, :error]
  attr :first, :boolean, default: false
  attr :last, :boolean, default: false
  slot :inner_block

  defp timeline_step(assigns) do
    ~H"""
    <li>
      <hr :if={!@first} class={timeline_connector_class(@status)} />
      <div class="timeline-middle">
        <.icon name={timeline_icon(@status)} class={["h-5 w-5", timeline_icon_class(@status)]} />
      </div>
      <div class="timeline-end py-2 text-start">
        <p class={["text-sm leading-tight", (@status == :pending && "text-base-content/65") || "text-base-content"]}>
          {@label}
        </p>
        <p class="text-base-content/55 text-xs">{render_slot(@inner_block)}</p>
      </div>
      <hr :if={!@last} class={timeline_connector_class(@status)} />
    </li>
    """
  end

  defp timeline_icon(:done), do: "hero-check-circle-solid"
  defp timeline_icon(:error), do: "hero-x-circle-solid"
  defp timeline_icon(:pending), do: "hero-clock"

  defp timeline_icon_class(:done), do: "text-success"
  defp timeline_icon_class(:error), do: "text-error"
  defp timeline_icon_class(:pending), do: "text-base-content/30"

  defp timeline_connector_class(:done), do: "bg-success"
  defp timeline_connector_class(_), do: ""

  # A refund still means payment was received, so it reads as done; a failure is a
  # distinct error state, not merely "not yet paid".
  defp payment_step_status(:paid), do: :done
  defp payment_step_status(:refunded), do: :done
  defp payment_step_status(:failed), do: :error
  defp payment_step_status(:pending), do: :pending

  defp payment_step_detail(:paid), do: ~t"Paid"
  defp payment_step_detail(:refunded), do: ~t"Refunded"
  defp payment_step_detail(:failed), do: ~t"Failed"
  defp payment_step_detail(:pending), do: ~t"Awaiting payment"

  attr :label, :string, required: true

  defp relative_date_badge(assigns) do
    ~H"""
    <span class="badge badge-soft badge-neutral badge-sm whitespace-nowrap first-letter:uppercase">
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
    <div :if={@directions} class="border-base-300/70 mt-6 overflow-hidden rounded-md border">
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
          <.icon name="hero-arrow-top-right-on-square" class="text-base-content/40 h-3.5 w-3.5" />
        </div>
      </a>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :amount, :any, default: nil
  attr :locale, :string, required: true
  attr :strong, :boolean, default: false

  defp money_row(assigns) do
    ~H"""
    <div class={["flex items-center justify-between gap-4 py-0.5", @strong && "border-base-300/70 text-base-content mt-1.5 border-t pt-3 text-base font-semibold"]}>
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

  defp fulfillment_emoji(:delivery), do: "🚚"
  defp fulfillment_emoji(:pickup), do: "🛍️"
  defp fulfillment_emoji(_), do: "❓"

  # The option name ("Home delivery") already conveys the method, so don't prefix
  # it with the bare method label; fall back to that label only when it's absent.
  defp fulfillment_description(order) do
    cond do
      present?(order.fulfillment_option_name) -> order.fulfillment_option_name
      present?(fulfillment_label(order.fulfillment_method)) -> fulfillment_label(order.fulfillment_method)
      true -> "—"
    end
  end

  # A fulfilled order is historical, so we skip relative framing there.
  defp fulfillment_relative(date, locale, status) when not is_nil(date) and status != :fulfilled do
    today = store_today()

    if Date.diff(date, today) == 0,
      do: Localize.DateTime.Relative.to_string!(0, unit: :day, locale: locale),
      else: Localize.DateTime.Relative.to_string!(date, relative_to: today, locale: locale)
  end

  defp fulfillment_relative(_date, _locale, _status), do: nil

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
      "&origin=#{URI.encode_www_form(@shop_origin)}" <>
      "&destination=#{URI.encode_www_form(destination)}" <>
      "&travelmode=driving"
  end

  defp fastmail_search_url(email) do
    "https://app.fastmail.com/mail/search:#{URI.encode_www_form(email)}"
  end
end

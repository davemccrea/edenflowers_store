defmodule EdenflowersWeb.AccountLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Order

  @contact_email "info@edenflowers.fi"
  @shop_address "Vaasanpuistikko 19, 65100 Vaasa"

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    today = Date.utc_today()

    open_orders = Order.get_open_orders!(actor: actor)
    past_orders = Order.get_past_orders!(actor: actor)

    user_with_name =
      Ash.load!(actor, [:first_name], actor: actor, authorize?: false)

    {:ok,
     socket
     |> assign(:open_orders, open_orders)
     |> assign(:past_orders, past_orders)
     |> assign(:today, today)
     |> assign(:user_first_name, user_first_name(user_with_name))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <header class="mb-16 max-w-3xl md:mb-20">
          <p :if={@current_user && @current_user.email} class="text-base-content/70 mb-2">
            {to_string(@current_user.email)}
          </p>
          <h1 class="page-title">{greeting(@user_first_name)}</h1>
        </header>

        <%= cond do %>
          <% Enum.any?(@open_orders) or Enum.any?(@past_orders) -> %>
            <section :if={Enum.any?(@open_orders)} class="mb-16 max-w-3xl">
              <h2 class="section-title mb-6">
                {~t"Open orders"} <span class="text-base-content/60">· {Enum.count(@open_orders)}</span>
              </h2>

              <ul class="space-y-6">
                <li :for={order <- @open_orders}>
                  <.open_order_card order={order} today={@today} />
                </li>
              </ul>
            </section>

            <section :if={Enum.any?(@past_orders)} class="max-w-3xl">
              <h2 class="section-title mb-6">
                {~t"Past orders"} <span class="text-base-content/60">· {Enum.count(@past_orders)}</span>
              </h2>

              <ul class="border-base-content/12 divide-base-content/12 divide-y border-t border-b">
                <li :for={order <- @past_orders} class="py-5">
                  <.past_order_row order={order} />
                </li>
              </ul>
            </section>
          <% true -> %>
            <p class="text-base-content/70 max-w-3xl">
              {~t"You haven't placed any orders yet."}
              <.link navigate={~p"/store"} class="link-underline-static-body">{~t"Visit the store"}</.link>
            </p>
        <% end %>

        <div class="mt-16 max-w-3xl">
          <.link href={~p"/sign-out"} class="link-underline-static-body text-base-content/70 text-sm">
            {~t"Sign out"}
          </.link>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  attr :order, :map, required: true
  attr :today, Date, required: true

  defp open_order_card(assigns) do
    thumbnail = first_non_card_line_item(assigns.order.line_items)
    assigns = assign(assigns, :thumbnail, thumbnail)

    ~H"""
    <article class="border-base-content/12 flex gap-4 rounded-lg border p-5 sm:gap-6 sm:p-6">
      <div :if={@thumbnail} class="shrink-0">
        <.image
          src={@thumbnail.product_image_slug}
          alt={@thumbnail.product_name}
          width={84}
          height={84}
          sizes="84px"
          class="h-21 w-21 rounded-md object-cover"
        />
      </div>

      <div class="min-w-0 flex-1 space-y-3">
        <div class="flex items-baseline justify-between gap-3">
          <p class="text-base-content/60 text-xs uppercase tracking-wide">
            {@order.order_reference}
          </p>
          <.order_status_badge status={@order.fulfillment_status} />
        </div>

        <div class="flex items-baseline gap-2">
          <h3 class="card-title">{@order.display_title}</h3>
          <span :if={@order.gift} class="text-warning" aria-label={~t"Gift order"} title={~t"Gift order"}>
            &#x2766;
          </span>
        </div>

        <p class="text-base-content/80">
          {format_fulfillment_prose(@order, @today)}
        </p>

        <p class="text-base-content/70 text-sm">
          {recipient_meta(@order)}
        </p>

        <p :if={@order.gift and present?(@order.card_message)} class="text-base-content/70 text-sm italic">
          &ldquo;{@order.card_message}&rdquo;
        </p>

        <p
          :if={@order.fulfillment_method == :delivery and present?(@order.delivery_instructions)}
          class="text-base-content/70 text-sm"
        >
          <span class="font-medium">{~t"Notes for courier"}:</span>
          {@order.delivery_instructions}
        </p>

        <div class="flex flex-wrap items-baseline justify-between gap-3 pt-2">
          <a href={mailto_for_order(@order)} class="link-underline-static-body font-medium">
            {~t"Message Jennie"} &rarr;
          </a>
          <span class="font-medium tabular-nums">
            {Edenflowers.Utils.format_money(@order.grand_total)}
          </span>
        </div>
      </div>
    </article>
    """
  end

  attr :order, :map, required: true

  defp past_order_row(assigns) do
    ~H"""
    <.link
      navigate={~p"/order/#{@order.id}"}
      class="group flex flex-col gap-1 sm:grid-cols-[auto_auto_1fr_auto_auto] sm:grid sm:items-baseline sm:gap-6"
    >
      <span class="text-base-content/70 text-sm tabular-nums">
        {format_ordered_at(@order.ordered_at)}
      </span>
      <span class="link-underline-hover-nav font-medium group-hover:text-base-content/70">
        {@order.order_reference}
      </span>
      <span class="text-base-content/80 truncate">
        {@order.display_title} <span class="text-base-content/60">{recipient_suffix(@order)}</span>
      </span>
      <span class="text-sm">
        <.order_status_badge status={@order.fulfillment_status} />
      </span>
      <span class="tabular-nums sm:text-right">
        {Edenflowers.Utils.format_money(@order.grand_total)}
      </span>
    </.link>
    """
  end

  attr :status, :atom, required: true

  defp order_status_badge(assigns) do
    ~H"""
    <span class={["inline-flex rounded-full px-2 py-0.5 text-xs", status_classes(@status)]}>
      {status_label(@status)}
    </span>
    """
  end

  defp status_label(:pending), do: ~t"Pending"
  defp status_label(:fulfilled), do: ~t"Fulfilled"

  defp status_classes(:pending), do: "bg-warning/15 text-warning-content"
  defp status_classes(:fulfilled), do: "bg-success/15 text-success-content"

  defp greeting(nil), do: ~t"Your account"
  defp greeting(first_name), do: ~t"Hej {name}" |> String.replace("{name}", first_name)

  defp user_first_name(%{first_name: name}) when is_binary(name) and name != "", do: name
  defp user_first_name(_), do: nil

  defp format_ordered_at(nil), do: ""

  defp format_ordered_at(%DateTime{} = dt) do
    locale = Localize.get_locale().cldr_locale_id
    Localize.Date.to_string!(DateTime.to_date(dt), locale: locale, format: :medium)
  end

  @doc """
  Renders the fulfillment date as friendly prose, varying by fulfillment
  method (delivery vs pickup) and proximity to `today`.

  Public for testability.
  """
  def format_fulfillment_prose(%{fulfillment_date: nil}, _today), do: ""

  def format_fulfillment_prose(%{fulfillment_date: date, fulfillment_method: method}, today) do
    cond do
      Date.compare(date, today) == :eq -> today_phrase(method)
      Date.compare(date, Date.add(today, 1)) == :eq -> tomorrow_phrase(method)
      true -> dated_future_phrase(method, date)
    end
  end

  defp today_phrase(:pickup), do: ~t"Ready for pickup today"
  defp today_phrase(_), do: ~t"Arriving today"

  defp tomorrow_phrase(:pickup), do: ~t"Ready for pickup tomorrow"
  defp tomorrow_phrase(_), do: ~t"Arriving tomorrow"

  defp dated_future_phrase(:pickup, date),
    do: ~t"Ready for pickup {date}" |> String.replace("{date}", format_date(date))

  defp dated_future_phrase(_, date),
    do: ~t"Arriving on {date}" |> String.replace("{date}", format_date(date))

  defp format_date(%Date{} = date) do
    locale = Localize.get_locale().cldr_locale_id
    Localize.Date.to_string!(date, locale: locale, format: :medium)
  end

  defp recipient_meta(%{fulfillment_method: :pickup}) do
    ~t"In-store pickup" <> " · " <> @shop_address
  end

  defp recipient_meta(%{recipient_name: name, delivery_address: addr}) do
    [name, addr]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp recipient_suffix(%{gift: true, recipient_name: name}) when is_binary(name) and name != "",
    do: ~t"to {name}" |> String.replace("{name}", name)

  defp recipient_suffix(_), do: ~t"for yourself"

  @doc """
  Builds the `mailto:` URL for the "Message Jennie" CTA. URL-encodes the
  subject so changes to the order-reference format remain safe.

  Public for testability.
  """
  def mailto_for_order(%{order_reference: ref}) do
    subject = URI.encode_www_form("Order " <> (ref || ""))
    "mailto:#{@contact_email}?subject=#{subject}"
  end

  defp first_non_card_line_item(line_items) when is_list(line_items) do
    line_items
    |> Enum.reject(& &1.is_card)
    |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
    |> List.first()
  end

  defp first_non_card_line_item(_), do: nil

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(str) when is_binary(str), do: String.trim(str) != ""
  defp present?(_), do: false
end

defmodule EdenflowersWeb.Admin.SubscriptionDetailLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  require Ash.Query

  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Translations
  alias EdenflowersWeb.Checkout.Fields
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case get_subscription(id, socket.assigns.current_user) do
      {:ok, subscription} ->
        {:ok,
         socket
         |> assign(:page_title, subscription.user.name || to_string(subscription.user.email))
         |> assign(:locale, Localize.get_locale())
         |> assign(:subscription, subscription)
         |> assign(:orders_query, Ash.Query.filter(Order, subscription_id == ^subscription.id))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Subscription not found.")
         |> push_navigate(to: ~p"/admin/subscriptions")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="wide">
        <.admin_page_header
          title={@subscription.user.name || ~t"Unnamed customer"}
          back={~p"/admin/subscriptions"}
          back_label={~t"Subscriptions"}
        >
          <:subtitle>
            <span class="inline-flex flex-wrap items-center gap-x-2">
              <span>{product_name(@subscription)}, {variant_size_label(@subscription.product_variant.size)}</span>
              <span aria-hidden="true">·</span>
              <span>{Fields.interval_label(@subscription.interval_weeks)}</span>
              <.subscription_state_badge state={@subscription.state} />
            </span>
          </:subtitle>
          <:actions>
            <.button
              :if={@subscription.state == :active}
              type="button"
              phx-click="pause"
              variant="ghost"
              size="sm"
            >
              {~t"Pause"}
            </.button>
            <.button
              :if={@subscription.state == :paused}
              type="button"
              phx-click="resume"
              variant="ghost"
              size="sm"
            >
              {~t"Resume"}
            </.button>
            <div :if={@subscription.state != :cancelled} class="dropdown sm:dropdown-end">
              <.icon_button tabindex="0" size="sm" aria_label={~t"More actions"}>
                <.icon name="hero-ellipsis-horizontal" class="h-5 w-5" />
              </.icon_button>
              <ul tabindex="0" class="dropdown-content menu bg-base-100 border-base-300 z-10 mt-2 w-44 border p-1 shadow">
                <li>
                  <button
                    type="button"
                    phx-click="cancel"
                    data-confirm={~t"Cancel this subscription? This can't be undone."}
                    class="text-error"
                  >
                    {~t"Cancel subscription"}
                  </button>
                </li>
              </ul>
            </div>
          </:actions>
        </.admin_page_header>

        <div class="mb-6 grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <.widget id="subscription-fulfillment" title={~t"Fulfillment"}>
            <div class="grid grid-cols-1 gap-x-8 gap-y-5 sm:grid-cols-3">
              <.summary_fact label={~t"Next delivery"}>
                <span :if={@subscription.state != :cancelled} class="tabular-nums">
                  {Format.weekday_day_month(@subscription.next_fulfillment_date, @locale)}
                </span>
                <.blank :if={@subscription.state == :cancelled} />
              </.summary_fact>
              <.summary_fact label={~t"Method"}>
                <.fulfillment_method
                  method={@subscription.fulfillment_option.fulfillment_method}
                  label={Translations.translate(@subscription.fulfillment_option).name}
                  class="whitespace-normal"
                />
              </.summary_fact>
              <.summary_fact :if={@subscription.delivery_address} label={~t"Deliver to"}>
                {@subscription.delivery_address}
              </.summary_fact>
            </div>

            <div
              :if={@subscription.delivery_instructions}
              class="bg-warning/15 border-warning/40 mt-5 flex gap-2.5 border px-3 py-2.5"
            >
              <.icon name="hero-information-circle" class="text-warning-content mt-0.5 h-5 w-5 shrink-0" />
              <div>
                <p class="text-warning-content text-sm font-semibold">{~t"Delivery instructions"}</p>
                <p class="text-base-content mt-0.5 whitespace-pre-wrap break-words">
                  {@subscription.delivery_instructions}
                </p>
              </div>
            </div>

            <div :if={@subscription.card_message} class="mt-5">
              <p class="eyebrow text-base-content/65 mb-1.5">{~t"Card message"}</p>
              <blockquote
                phx-no-format
                class="text-base-content font-serif whitespace-pre-wrap break-words text-lg italic leading-relaxed"
              >{@subscription.card_message}</blockquote>
            </div>
          </.widget>

          <aside class="flex flex-col gap-6">
            <.widget id="subscription-customer" title={~t"Customer"}>
              <div class="space-y-1.5 text-sm">
                <p><.email_link email={@subscription.user.email} /></p>
                <p>
                  <.link
                    id="subscription-customer-link"
                    navigate={~p"/admin/customers/#{@subscription.user_id}"}
                    class="link link-primary inline-flex items-center gap-1.5"
                  >
                    <.icon name="hero-user" class="h-3.5 w-3.5 shrink-0" />
                    {~t"View customer's orders"}
                  </.link>
                </p>
              </div>
            </.widget>

            <.widget :if={@subscription.recipient_name} id="subscription-recipient" title={~t"Recipient"}>
              <div class="space-y-1.5">
                <p class="text-base-content text-base font-medium">{@subscription.recipient_name}</p>
                <p :if={@subscription.recipient_phone_number} class="text-sm tabular-nums">
                  {@subscription.recipient_phone_number}
                </p>
              </div>
            </.widget>

            <.widget id="subscription-card" title={~t"Card on file"}>
              <p :if={Fields.card_label(@subscription)} class="text-sm">{Fields.card_label(@subscription)}</p>
              <.blank :if={is_nil(Fields.card_label(@subscription))} />
            </.widget>
          </aside>
        </div>

        <h2 class="text-base-content mb-4 text-base font-semibold">{~t"Orders"}</h2>

        <Cinder.collection
          id="subscription-orders-table"
          query={@orders_query}
          action={:admin_list}
          actor={@current_user}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn order -> JS.navigate(~p"/admin/orders/#{order.id}") end}
        >
          <:col :let={order} field="fulfillment_date" sort={[cycle: [:desc, :asc]]} label={~t"Fulfillment date"}>
            <.link
              navigate={~p"/admin/orders/#{order.id}"}
              class="whitespace-nowrap font-medium tabular-nums hover:underline"
            >
              {Format.date(order.fulfillment_date, @locale)}
            </.link>
            <div class="text-base-content/65 mt-0.5 text-sm tabular-nums">{order.order_reference}</div>
            <div class="mt-1 sm:hidden">
              <.payment_status_badge status={order.payment_status} />
            </div>
          </:col>
          <:col :let={order} field="fulfillment_status" sort label={~t"Fulfillment"}>
            <.fulfillment_status_badge status={order.fulfillment_status} />
          </:col>
          <:col :let={order} field="payment_status" sort label={~t"Payment"} class="max-sm:hidden">
            <.payment_status_badge status={order.payment_status} />
          </:col>
          <:col :let={order} field="grand_total" sort label={~t"Total"} class="text-right">
            <span class="whitespace-nowrap tabular-nums">{Format.currency(order.grand_total, @locale)}</span>
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("pause", _params, socket) do
    {:noreply, change_subscription(socket, &Orders.pause_subscription/2, ~t"Subscription paused.")}
  end

  def handle_event("resume", _params, socket) do
    {:noreply, change_subscription(socket, &Orders.resume_subscription/2, ~t"Subscription resumed.")}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, change_subscription(socket, &Orders.cancel_subscription/2, ~t"Subscription cancelled.")}
  end

  defp change_subscription(socket, action, success_message) do
    actor = socket.assigns.current_user

    with {:ok, _} <- action.(socket.assigns.subscription, actor: actor),
         {:ok, subscription} <- get_subscription(socket.assigns.subscription.id, actor) do
      socket
      |> assign(:subscription, subscription)
      |> put_flash(:info, success_message)
      |> Cinder.refresh_table("subscription-orders-table")
    else
      _ -> put_flash(socket, :error, ~t"Could not change the subscription.")
    end
  end

  defp get_subscription(id, actor) do
    Orders.get_subscription(id,
      actor: actor,
      load: [:user, :fulfillment_option, product_variant: :product]
    )
  end

  defp product_name(subscription), do: Translations.translate(subscription.product_variant.product).name
end

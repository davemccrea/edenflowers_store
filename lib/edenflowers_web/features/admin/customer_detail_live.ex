defmodule EdenflowersWeb.Admin.CustomerDetailLive do
  @moduledoc """
  Admin view of a customer, their orders, and their subscriptions.
  """

  use EdenflowersWeb, :live_view

  require Ash.Query

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.User
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Subscription
  alias EdenflowersWeb.Checkout.Fields
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_customer_for_admin(id, actor: socket.assigns.current_user) do
      {:ok, %User{} = customer} ->
        if connected?(socket) do
          EdenflowersWeb.Endpoint.subscribe("admin:orders")
          EdenflowersWeb.Endpoint.subscribe("admin:subscriptions")
        end

        {:ok,
         socket
         |> assign(:page_title, customer.name || to_string(customer.email))
         |> assign(:locale, Localize.get_locale())
         |> assign(:customer, customer)
         |> assign(:orders_query, Ash.Query.filter(Order, user_id == ^customer.id))
         |> assign(:subscriptions_query, Ash.Query.filter(Subscription, user_id == ^customer.id))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Customer not found.")
         |> push_navigate(to: ~p"/admin/customers")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header
          title={@customer.name || ~t"Unnamed customer"}
          back={{~t"Customers", ~p"/admin/customers"}}
        >
          <:subtitle>
            <.email_link email={@customer.email} />
          </:subtitle>
        </.admin_page_header>

        <section
          id="customer-summary"
          class="admin-card mb-6 grid grid-cols-2 gap-x-8 gap-y-5 p-4 sm:grid-cols-4 sm:p-5"
        >
          <.summary_fact label={~t"Orders"}>
            <span class="tabular-nums">{@customer.placed_order_count}</span>
          </.summary_fact>
          <.summary_fact label={~t"Total spent"}>
            <span class="tabular-nums">{Format.currency(@customer.total_spent, @locale)}</span>
          </.summary_fact>
          <.summary_fact label={~t"Last order"}>
            <span :if={@customer.last_ordered_at} class="tabular-nums">{Format.date(@customer.last_ordered_at, @locale)}</span>
            <.blank :if={is_nil(@customer.last_ordered_at)} />
          </.summary_fact>
          <.summary_fact label={~t"Newsletter"}>
            {if @customer.newsletter_opt_in, do: ~t"Subscribed", else: ~t"Not subscribed"}
          </.summary_fact>
        </section>

        <h2 class="text-base-content mb-4 text-base font-semibold">{~t"Subscriptions"}</h2>

        <Cinder.collection
          id="customer-subscriptions-table"
          query={@subscriptions_query}
          action={:admin_list}
          actor={@current_user}
          sort_mode="exclusive"
          page_size={[default: 10, options: [10, 25, 50]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          class="mb-8"
          click={fn subscription -> JS.navigate(~p"/admin/subscriptions/#{subscription.id}") end}
        >
          <:col :let={subscription} field="product_variant.size" sort label={~t"Size"}>
            <.link navigate={~p"/admin/subscriptions/#{subscription.id}"} class="touch-target font-medium hover:underline">
              {variant_size_label(subscription.product_variant.size)}
            </.link>
          </:col>
          <:col :let={subscription} field="interval_weeks" sort label={~t"Interval"} class="max-sm:hidden">
            {Fields.interval_label(subscription.interval_weeks)}
          </:col>
          <:col :let={subscription} field="next_fulfillment_date" sort={[cycle: [:asc, :desc]]} label={~t"Next delivery"}>
            <span :if={subscription.next_delivery_date} class="whitespace-nowrap tabular-nums">
              {Format.date(subscription.next_delivery_date, @locale)}
            </span>
            <.blank :if={!subscription.next_delivery_date} />
          </:col>
          <:col :let={subscription} field="state" sort label={~t"Status"}>
            <.subscription_state_badge state={subscription.state} />
          </:col>
        </Cinder.collection>

        <h2 class="text-base-content mb-4 text-base font-semibold">{~t"Orders"}</h2>

        <Cinder.collection
          id="customer-orders-table"
          query={@orders_query}
          action={:admin_list}
          actor={@current_user}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn order -> JS.navigate(~p"/admin/orders/#{order.id}") end}
        >
          <:col :let={order} field="ordered_at" sort={[cycle: [:desc, :asc]]} label={~t"Ordered"}>
            <.link
              navigate={~p"/admin/orders/#{order.id}"}
              class="touch-target whitespace-nowrap font-medium tabular-nums hover:underline"
            >
              {Format.date(order.ordered_at, @locale)}
            </.link>
          </:col>
          <:col :let={order} label={~t"Reference"} class="max-sm:hidden">
            <span class="text-base-content/75 tabular-nums">{order.order_reference}</span>
          </:col>
          <:col
            :let={order}
            field="fulfillment_date"
            sort={[cycle: [nil, :desc, :asc]]}
            label={~t"Fulfillment date"}
            class="max-sm:hidden"
          >
            <span class="whitespace-nowrap tabular-nums">
              {Format.date(order.fulfillment_date, @locale)}
            </span>
          </:col>
          <:col :let={order} field="fulfillment_status" sort label={~t"Fulfillment"}>
            <.fulfillment_status_badge status={order.fulfillment_status} />
          </:col>
          <:col :let={order} field="payment_status" sort label={~t"Payment"} class="max-sm:hidden">
            <.order_payment_badge order={order} locale={@locale} />
          </:col>
          <:col :let={order} field="grand_total" sort label={~t"Total"} class="text-right">
            <span class="whitespace-nowrap tabular-nums">
              {Format.currency(order.grand_total, @locale)}
            </span>
          </:col>
          <:col :let={order} field="fulfillment_method" sort label={~t"Method"} class="max-sm:hidden">
            <.fulfillment_method method={order.fulfillment_method} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "admin:orders"}, socket),
    do: {:noreply, Cinder.refresh_table(socket, "customer-orders-table")}

  def handle_info(%Phoenix.Socket.Broadcast{topic: "admin:subscriptions"}, socket),
    do: {:noreply, Cinder.refresh_table(socket, "customer-subscriptions-table")}
end

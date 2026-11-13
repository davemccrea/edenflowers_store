defmodule EdenflowersWeb.Admin.OrdersLive do
  @moduledoc """
  Searchable, sortable admin order list. It opens on open orders, soonest
  fulfillment date first, so overdue and today's orders lead.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Events
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias EdenflowersWeb.Admin.DefaultTableView
  alias EdenflowersWeb.Admin.PubSub
  alias EdenflowersWeb.Layouts

  @default_view %{"open" => "true", "sort" => "fulfillment_date"}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe([Events.admin_orders()])

    {:ok,
     socket
     |> assign(:page_title, ~t"Orders")
     |> assign(:locale, Localize.get_locale())}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, DefaultTableView.handle_params(params, uri, socket, @default_view)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Orders"}>
          <:actions>
            <.button navigate={~p"/admin/orders/new"} variant="primary" size="sm" class="sm:order-last">
              <.icon name="hero-plus" class="h-4 w-4" /> {~t"New order"}
            </.button>
            <.button navigate={~p"/admin/orders/new-gift-voucher"} variant="secondary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" /> {~t"New voucher"}
            </.button>
          </:actions>
        </.admin_page_header>

        <Cinder.collection
          id="orders-table"
          resource={Order}
          action={:admin_list}
          actor={@current_user}
          search={[
            label: ~t"Search",
            placeholder: ~t"Search orders…",
            fn: fn query, _columns, term -> Ash.Query.set_argument(query, :term, term) end
          ]}
          url_state={@url_state}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          pagination={[mode: :offset, count: :async]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn order -> JS.navigate(~p"/admin/orders/#{order.id}") end}
        >
          <:filter
            field="open"
            type={:select}
            label={~t"Show"}
            prompt={~t"All orders"}
            options={[
              {~t"Still to do", "true"},
              {~t"All unfinished", "unfinished"},
              {~t"To make", "pending"},
              {~t"Ready", "ready"},
              {~t"Gift orders", "gift"}
            ]}
            fn={fn query, %{value: value} -> Ash.Query.set_argument(query, :show, value) end}
          />
          <:filter
            field="kind"
            type={:select}
            label={~t"Kind"}
            prompt={~t"All"}
            options={[{~t"Flowers", "flowers"}, {~t"Gift vouchers", "gift_vouchers"}]}
            fn={fn query, %{value: value} -> Ash.Query.set_argument(query, :kind, value) end}
          />
          <:col :let={order} field="ordered_at" sort label={~t"Ordered"} class="max-sm:hidden">
            <span class="tabular-nums">{Format.date(order.ordered_at, @locale)}</span>
          </:col>
          <:col :let={order} field="customer_name" search sort label={~t"Customer"}>
            <.link
              navigate={~p"/admin/orders/#{order.id}"}
              class="max-w-28 inline-block truncate align-middle font-semibold hover:underline sm:max-w-none"
            >
              {order.customer_name || ~t"Unnamed customer"}
            </.link>
            <.subscription_badge :if={order.origin == :subscription} class="ml-1.5 max-sm:hidden" />
            <.badge
              :if={order.voucher_card_to_hand_over?}
              tone={:attention}
              icon="hero-pencil-square"
              class="ml-1.5 align-middle max-sm:hidden"
            >
              {~t"Card"}
            </.badge>
          </:col>
          <:col :let={order} field="fulfillment_date" sort label={~t"Fulfillment date"}>
            <span :if={order.gift_voucher_sale?} class="text-base-content/75">{~t"Gift voucher"}</span>
            <span
              :if={!order.gift_voucher_sale?}
              class={["tabular-nums", order.overdue? && "max-sm:text-error max-sm:font-semibold"]}
            >
              <span class="max-sm:hidden">{Format.date(order.fulfillment_date, @locale)}</span>
              <span class="sm:hidden">{Format.day_month(order.fulfillment_date, @locale)}</span>
              <span :if={order.overdue?} class="sr-only sm:hidden">{~t"Overdue"}</span>
            </span>
            <.badge :if={order.overdue?} tone={:error} class="ml-1.5 align-middle max-sm:hidden">
              {~t"Overdue"}
            </.badge>
          </:col>
          <:col
            :let={order}
            field="fulfillment_status"
            sort
            label={~t"Fulfillment"}
          >
            <.fulfillment_status_badge status={order.fulfillment_status} method={order.fulfillment_method} />
          </:col>
          <:col
            :let={order}
            field="payment_status"
            sort
            filter={[
              type: :select,
              label: ~t"Payment",
              prompt: ~t"All",
              options: payment_status_options()
            ]}
            label={~t"Payment"}
            class="max-sm:hidden"
          >
            <.order_payment_badge order={order} locale={@locale} />
          </:col>
          <:col :let={order} field="grand_total" sort label={~t"Total"} class="text-right max-sm:hidden">
            <span class="tabular-nums">{Format.currency(order.grand_total, @locale)}</span>
          </:col>
          <:col
            :let={order}
            field="fulfillment_method"
            sort
            filter={[
              type: :select,
              label: ~t"Delivery or pickup",
              prompt: ~t"All",
              options: fulfillment_method_options()
            ]}
            label={~t"Method"}
            class="max-sm:hidden"
          >
            <.fulfillment_method :if={order.fulfillment_method} method={order.fulfillment_method} />
            <.blank :if={!order.fulfillment_method} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: _topic}, socket),
    do: {:noreply, PubSub.schedule_refresh(socket, :orders_table)}

  def handle_info({:admin_refresh, :orders_table}, socket),
    do: {:noreply, Cinder.refresh_table(socket, "orders-table")}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp fulfillment_method_options do
    Edenflowers.Fulfillment.FulfillmentOption.FulfillmentMethod.values()
    |> Enum.map(fn value -> {fulfillment_method_label(value), value} end)
  end

  defp payment_status_options do
    Enum.map(Order.Types.PaymentStatus.values(), &{payment_status_label(&1), &1})
  end
end

defmodule EdenflowersWeb.Admin.OrdersLive do
  @moduledoc """
  Searchable, sortable admin order list. It opens on open orders, soonest
  fulfillment date first.
  """

  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias EdenflowersWeb.Admin.DefaultTableView
  alias EdenflowersWeb.Layouts

  # Open orders, soonest first, so overdue ones lead.
  @default_view %{"open" => "true", "sort" => "fulfillment_date"}

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: EdenflowersWeb.Endpoint.subscribe("admin:orders")

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
            <.button navigate={~p"/admin/orders/new"} variant="primary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" /> {~t"New order"}
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
            fn: &search_orders/3
          ]}
          url_state={@url_state}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn order -> JS.navigate(~p"/admin/orders/#{order.id}") end}
        >
          <:filter
            field="open"
            type={:select}
            label={~t"Show"}
            prompt={~t"All orders"}
            options={[{~t"Still to do", "true"}]}
            fn={&open_orders/2}
          />
          <:col :let={order} field="customer_name" search sort label={~t"Customer"}>
            <.link
              navigate={~p"/admin/orders/#{order.id}"}
              class="max-w-28 inline-block truncate align-middle font-medium hover:underline sm:max-w-none"
            >
              {order.customer_name || ~t"Unnamed customer"}
            </.link>
            <.subscription_badge :if={order.origin == :subscription} class="ml-1.5 max-sm:hidden" />
          </:col>
          <:col
            :let={order}
            field="fulfillment_date"
            sort={[cycle: [:asc, :desc]]}
            label={~t"Fulfillment date"}
          >
            <span class={["tabular-nums", order.overdue? && "max-sm:text-error max-sm:font-semibold"]}>
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
            <.fulfillment_status_badge status={order.fulfillment_status} />
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
            <.fulfillment_method method={order.fulfillment_method} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "admin:orders"}, socket),
    do: {:noreply, Cinder.refresh_table(socket, "orders-table")}

  defp open_orders(query, _filter) do
    require Ash.Query
    Ash.Query.filter(query, open?)
  end

  defp search_orders(query, _searchable_columns, search_term) do
    require Ash.Query
    term = Ash.CiString.new(search_term)
    Ash.Query.filter(query, matches?(term: ^term))
  end

  defp fulfillment_method_options do
    Edenflowers.Fulfillment.FulfillmentOption.FulfillmentMethod.values()
    |> Enum.map(fn value -> {fulfillment_method_label(value), value} end)
  end

  # A placed order whose payment is still pending is unpaid, so the filter says so.
  defp payment_status_options do
    Enum.map(Order.Types.PaymentStatus.values(), fn
      :pending -> {~t"Unpaid", :pending}
      value -> {status_label(value), value}
    end)
  end

  defp status_label(:paid), do: ~t"Paid"
  defp status_label(:refunded), do: ~t"Refunded"
end

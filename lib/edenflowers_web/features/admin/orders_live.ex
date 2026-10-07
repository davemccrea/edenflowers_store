defmodule EdenflowersWeb.Admin.OrdersLive do
  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Orders.Order
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Orders")
     |> assign(:locale, Localize.get_locale())
     |> assign(:today, DateTime.now!("Europe/Helsinki") |> DateTime.to_date())}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="full">
        <.admin_page_header title={~t"Orders"}>
          <:actions>
            <.button navigate={~p"/admin/orders/new"} variant="neutral" size="sm">
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
            label: ~t"Order",
            placeholder: ~t"Search name or order number…",
            fn: &search_orders/3
          ]}
          url_state={@url_state}
          show_filters={:toggle}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn order -> JS.navigate(~p"/admin/orders/#{order.id}") end}
        >
          <:col
            :let={order}
            field="fulfillment_date"
            sort={[cycle: [:asc, :desc]]}
            label={~t"Fulfillment date"}
          >
            <span class="whitespace-nowrap tabular-nums">
              {Format.date(order.fulfillment_date, @locale)}
            </span>
            <span
              :if={overdue?(order, @today)}
              class="badge badge-sm admin-badge-error ml-1.5 whitespace-nowrap align-middle font-medium"
            >
              {~t"Overdue"}
            </span>
          </:col>
          <:col :let={order} field="customer_name" search sort label={~t"Customer"}>
            <.link navigate={~p"/admin/orders/#{order.id}"} class="font-medium hover:underline">
              {order.customer_name || ~t"Unnamed customer"}
            </.link>
          </:col>
          <:col
            :let={order}
            field="fulfillment_status"
            sort
            filter={[
              type: :select,
              label: ~t"Fulfillment status",
              prompt: ~t"All",
              options: fulfillment_status_options()
            ]}
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
              label: ~t"Payment status",
              prompt: ~t"All",
              options: payment_status_options()
            ]}
            label={~t"Payment"}
            class="max-sm:hidden"
          >
            <.payment_status_badge status={shown_payment_status(order)} />
          </:col>
          <:col :let={order} field="grand_total" label={~t"Total"}>
            <span class="whitespace-nowrap tabular-nums">
              {Format.currency(order.grand_total, @locale)}
            </span>
            <span
              :if={order.amount_mismatch? && order.fulfillment_status != :cancelled}
              class={["badge badge-sm ml-1.5 whitespace-nowrap align-middle font-medium", if(Decimal.positive?(order.balance), do: "admin-badge-warning", else: "admin-badge-error")]}
            >
              <%= if Decimal.positive?(order.balance) do %>
                {~t"To collect #{amount = Format.currency(order.balance, @locale)}"}
              <% else %>
                {~t"To refund #{amount = Format.currency(Decimal.abs(order.balance), @locale)}"}
              <% end %>
            </span>
          </:col>
          <:col
            :let={order}
            field="fulfillment_method"
            sort
            filter={[
              type: :select,
              label: ~t"Fulfillment method",
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

  defp overdue?(%{fulfillment_status: :pending, fulfillment_date: %Date{} = date}, today),
    do: Date.before?(date, today)

  defp overdue?(_order, _today), do: false

  defp search_orders(query, _searchable_columns, search_term) do
    require Ash.Query
    import Ash.Expr

    case_insensitive_term = Ash.CiString.new(search_term)

    Ash.Query.filter(
      query,
      expr(
        contains(customer_name, ^case_insensitive_term) or
          contains(order_reference, ^case_insensitive_term) or
          contains(customer_phone_number, ^case_insensitive_term)
      )
    )
  end

  # Reuse the enum's own values and the shared method labels so the filter options
  # can't drift from the type definition or the cell rendering.
  defp fulfillment_method_options do
    Edenflowers.Fulfillment.FulfillmentOption.FulfillmentMethod.values()
    |> Enum.map(fn value -> {fulfillment_method_label(value), value} end)
  end

  # A placed order whose payment is still pending is unpaid, so the filter says so.
  defp payment_status_options do
    Enum.map(Order.PaymentStatus.values(), fn
      :pending -> {~t"Unpaid", :pending}
      value -> {status_label(value), value}
    end)
  end

  defp fulfillment_status_options, do: select_options(Order.FulfillmentStatus)

  defp select_options(enum), do: Enum.map(enum.values(), &{status_label(&1), &1})

  defp status_label(:paid), do: ~t"Paid"
  defp status_label(:failed), do: ~t"Failed"
  defp status_label(:refunded), do: ~t"Refunded"
  defp status_label(:pending), do: ~t"Pending"
  defp status_label(:cancelled), do: ~t"Cancelled"
  defp status_label(:fulfilled), do: ~t"Fulfilled"
  defp status_label(value), do: to_string(value)
end

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
     |> assign(:locale, Localize.get_locale())}
  end

  @doc "The orders list filtered to the work still to do: paid and not yet fulfilled."
  def default_path, do: ~p"/admin/orders?fulfillment_status=pending&payment_status=paid"

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="full">
        <.admin_page_header title={~t"Orders"} />

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
          >
            <.payment_status_badge status={order.payment_status} />
          </:col>
          <:col :let={order} field="grand_total" label={~t"Total"}>
            <span class="whitespace-nowrap tabular-nums">
              {Format.currency(order.grand_total, @locale)}
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
          >
            <.fulfillment_method method={order.fulfillment_method} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp search_orders(query, _searchable_columns, search_term) do
    require Ash.Query
    import Ash.Expr

    case_insensitive_term = Ash.CiString.new(search_term)

    Ash.Query.filter(
      query,
      expr(
        contains(customer_name, ^case_insensitive_term) or
          contains(order_reference, ^case_insensitive_term)
      )
    )
  end

  # Reuse the enum's own values and the shared method labels so the filter options
  # can't drift from the type definition or the cell rendering.
  defp fulfillment_method_options do
    Edenflowers.Fulfillment.FulfillmentOption.FulfillmentMethod.values()
    |> Enum.map(fn value -> {fulfillment_method_label(value), value} end)
  end

  # Built from the resource's own one_of constraints so the select options
  # can't drift from the attribute definition.
  defp payment_status_options, do: select_options(:payment_status)
  defp fulfillment_status_options, do: select_options(:fulfillment_status)

  defp select_options(attribute) do
    Order
    |> Ash.Resource.Info.attribute(attribute)
    |> Map.fetch!(:constraints)
    |> Keyword.fetch!(:one_of)
    |> Enum.map(fn value -> {status_label(value), value} end)
  end

  defp status_label(:paid), do: ~t"Paid"
  defp status_label(:failed), do: ~t"Failed"
  defp status_label(:refunded), do: ~t"Refunded"
  defp status_label(:pending), do: ~t"Pending"
  defp status_label(:fulfilled), do: ~t"Fulfilled"
  defp status_label(value), do: to_string(value)
end

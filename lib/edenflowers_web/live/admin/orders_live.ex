defmodule EdenflowersWeb.Admin.OrdersLive do
  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Store.Order
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Orders")
     |> assign(:locale, Localize.get_locale())}
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
        <.admin_page_header title="Orders" />

        <Cinder.collection
          id="orders-table"
          resource={Order}
          action={:admin_list}
          actor={@current_user}
          search={[label: "Customer", placeholder: "Search by name…"]}
          url_state={@url_state}
          show_filters={:toggle}
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
        >
          <:col :let={order} field="customer_name" search label="Customer">
            <span class="font-medium">{order.customer_name || "—"}</span>
          </:col>
          <:col :let={order} field="ordered_at" sort={[cycle: [:desc, :asc]]} label="Date">
            <span class="whitespace-nowrap tabular-nums">
              {Format.datetime(order.ordered_at, @locale)}
            </span>
          </:col>
          <:col :let={order} field="fulfillment_date" sort={[cycle: [:asc, :desc]]} label="Fulfillment date">
            <span class="whitespace-nowrap tabular-nums">
              {Format.date(order.fulfillment_date, @locale)}
            </span>
          </:col>
          <:col
            :let={order}
            field="fulfillment_method"
            filter={[type: :select, label: "Fulfillment method", prompt: "All", options: fulfillment_method_options()]}
            label="Method"
          >
            <span class="inline-flex items-center gap-1.5 whitespace-nowrap">
              <.icon name={fulfillment_icon(order.fulfillment_method)} class="text-base-content/65 h-4 w-4" />
              {fulfillment_label(order.fulfillment_method)}
            </span>
          </:col>
          <:col :let={order} field="grand_total" label="Total">
            <span class="whitespace-nowrap tabular-nums">
              {Format.currency(order.grand_total, @locale)}
            </span>
          </:col>
          <:col
            :let={order}
            field="payment_status"
            filter={[type: :select, label: "Payment status", prompt: "All", options: payment_status_options()]}
            label="Payment"
          >
            <.payment_status_badge status={order.payment_status} />
          </:col>
          <:col
            :let={order}
            field="fulfillment_status"
            filter={[type: :select, label: "Fulfillment status", prompt: "All", options: fulfillment_status_options()]}
            label="Fulfillment"
          >
            <.fulfillment_status_badge status={order.fulfillment_status} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp fulfillment_icon(:delivery), do: "hero-truck"
  defp fulfillment_icon(:pickup), do: "hero-building-storefront"
  defp fulfillment_icon(_), do: "hero-question-mark-circle"

  defp fulfillment_label(:delivery), do: "Delivery"
  defp fulfillment_label(:pickup), do: "Pickup"
  defp fulfillment_label(_), do: "Unknown"

  # Reuse the enum's own values and the label map above so the filter options
  # can't drift from the type definition or the cell rendering.
  defp fulfillment_method_options do
    Edenflowers.Store.FulfillmentOption.FulfillmentMethod.values()
    |> Enum.map(fn value -> {fulfillment_label(value), value} end)
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
    |> Enum.map(fn value -> {humanize(value), value} end)
  end

  defp humanize(value) do
    value |> to_string() |> String.capitalize()
  end
end

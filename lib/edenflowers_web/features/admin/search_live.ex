defmodule EdenflowersWeb.Admin.SearchLive do
  use EdenflowersWeb, :live_view

  require Ash.Query

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Accounts.User
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias EdenflowersWeb.Layouts

  @limit 10

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:locale, Localize.get_locale()) |> assign(:limit, @limit)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    term = String.trim(params["q"] || "")
    actor = socket.assigns.current_user

    {orders, customers} =
      if term == "", do: {[], []}, else: {search_orders(term, actor), search_customers(term, actor)}

    {:noreply,
     socket
     |> assign(:page_title, ~t"Search")
     |> assign(:term, term)
     |> assign(:orders, orders)
     |> assign(:customers, customers)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Search"}>
          <:subtitle :if={@term != ""}>{~t"Results for “#{term = @term}”"}</:subtitle>
        </.admin_page_header>

        <p :if={@term == ""} class="text-base-content/65 text-sm">
          {~t"Search orders by name, reference, phone, email or delivery address, and customers by name or email."}
        </p>

        <div :if={@term != ""} class="grid grid-cols-1 gap-6 xl:grid-cols-2 xl:items-start">
          <.widget id="search-orders" title={~t"Orders"} count={length(@orders)}>
            <ul :if={@orders != []} class="divide-base-content/8 -my-2 divide-y">
              <li :for={order <- @orders}>
                <.link
                  navigate={~p"/admin/orders/#{order.id}"}
                  class="flex items-center justify-between gap-4 py-2.5 hover:underline"
                >
                  <span class="min-w-0">
                    <span class="text-base-content block truncate font-medium">{order.customer_name}</span>
                    <span class="text-base-content/65 text-sm tabular-nums">
                      {order.order_reference} · {Format.date(order.fulfillment_date, @locale)}
                    </span>
                  </span>
                  <.order_payment_badge order={order} locale={@locale} />
                </.link>
              </li>
            </ul>
            <p :if={@orders == []} class="text-base-content/65 text-sm">{~t"No orders found."}</p>
            <.link
              :if={length(@orders) == @limit}
              navigate={~p"/admin/orders?#{%{search: @term}}"}
              class="link link-primary touch-target mt-3 inline-block text-sm"
            >
              {~t"See all matching orders"}
            </.link>
          </.widget>

          <.widget id="search-customers" title={~t"Customers"} count={length(@customers)}>
            <ul :if={@customers != []} class="divide-base-content/8 -my-2 divide-y">
              <li :for={customer <- @customers}>
                <.link navigate={~p"/admin/customers/#{customer.id}"} class="block py-2.5 hover:underline">
                  <span class="text-base-content block truncate font-medium">{customer.name || customer.email}</span>
                  <span :if={customer.name} class="text-base-content/65 text-sm">{customer.email}</span>
                </.link>
              </li>
            </ul>
            <p :if={@customers == []} class="text-base-content/65 text-sm">{~t"No customers found."}</p>
            <.link
              :if={length(@customers) == @limit}
              navigate={~p"/admin/customers?#{%{search: @term}}"}
              class="link link-primary touch-target mt-3 inline-block text-sm"
            >
              {~t"See all matching customers"}
            </.link>
          </.widget>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp search_orders(term, actor) do
    term = Ash.CiString.new(term)

    Order
    |> Ash.Query.for_read(:admin_list, %{}, actor: actor)
    |> Ash.Query.filter(
      contains(customer_name, ^term) or contains(order_reference, ^term) or
        contains(customer_phone_number, ^term) or contains(customer_email, ^term) or
        contains(recipient_name, ^term) or contains(delivery_address, ^term)
    )
    |> Ash.Query.limit(@limit)
    |> Ash.read!()
  end

  defp search_customers(term, actor) do
    term = Ash.CiString.new(term)

    User
    |> Ash.Query.for_read(:admin_list, %{}, actor: actor)
    |> Ash.Query.filter(contains(name, ^term) or contains(email, ^term))
    |> Ash.Query.limit(@limit)
    |> Ash.read!()
  end
end

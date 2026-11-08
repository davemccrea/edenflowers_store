defmodule EdenflowersWeb.Admin.SearchLive do
  @moduledoc """
  Back-office search across orders and customers.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Accounts
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias EdenflowersWeb.Layouts

  @limit 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:locale, Localize.get_locale()) |> assign(:limit, @limit)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    term = String.trim(params["q"] || "")
    actor = socket.assigns.current_user

    {orders, customers} =
      if term == "" do
        {[], []}
      else
        {Orders.search_orders!(term, actor: actor, query: [limit: @limit]),
         Accounts.search_customers!(term, actor: actor, query: [limit: @limit])}
      end

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
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user} search_term={@term}>
      <.admin_page>
        <.admin_page_header title={~t"Search"}>
          <:subtitle :if={@term != ""}>{~t"Results for “#{term = @term}”"}</:subtitle>
        </.admin_page_header>

        <p :if={@term != "" and @orders == [] and @customers == []} class="text-base-content/75 text-sm">
          {~t"No orders or customers match “#{term = @term}”."}
        </p>

        <div :if={@orders != [] or @customers != []} class="grid grid-cols-1 gap-6 xl:grid-cols-2 xl:items-start">
          <.widget id="search-orders" title={~t"Orders"} count={shown_count(@orders, @limit)}>
            <ul :if={@orders != []} class="divide-base-content/12 -my-2 divide-y">
              <li :for={order <- @orders}>
                <.link
                  navigate={~p"/admin/orders/#{order.id}"}
                  class="flex items-center justify-between gap-4 py-2.5 hover:underline"
                >
                  <span class="min-w-0">
                    <span class="text-base-content block truncate font-semibold">{order.customer_name}</span>
                    <span class="text-base-content/75 text-sm tabular-nums">
                      {order.order_reference} · {Format.date(order.fulfillment_date, @locale)}
                    </span>
                  </span>
                  <.order_payment_badge order={order} locale={@locale} />
                </.link>
              </li>
            </ul>
            <p :if={@orders == []} class="text-base-content/75 text-sm">{~t"No orders found."}</p>
            <.link
              :if={length(@orders) == @limit}
              navigate={~p"/admin/orders?#{%{search: @term}}"}
              class="link link-primary touch-target mt-3 inline-block text-sm"
            >
              {~t"See all matching orders"}
            </.link>
          </.widget>

          <.widget id="search-customers" title={~t"Customers"} count={shown_count(@customers, @limit)}>
            <ul :if={@customers != []} class="divide-base-content/12 -my-2 divide-y">
              <li :for={customer <- @customers}>
                <.link navigate={~p"/admin/customers/#{customer.id}"} class="block py-2.5 hover:underline">
                  <span class="text-base-content block truncate font-semibold">{customer.name || customer.email}</span>
                  <span :if={customer.name} class="text-base-content/75 text-sm">{customer.email}</span>
                </.link>
              </li>
            </ul>
            <p :if={@customers == []} class="text-base-content/75 text-sm">{~t"No customers found."}</p>
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

  # At the limit the count is only the page size, and "See all" says there are more.
  defp shown_count(results, limit) when length(results) < limit, do: length(results)
  defp shown_count(_results, _limit), do: nil
end

defmodule EdenflowersWeb.Admin.CustomerDetailLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  require Ash.Query

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.User
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_customer_for_admin(id, actor: socket.assigns.current_user) do
      {:ok, %User{} = customer} ->
        {:ok,
         socket
         |> assign(:page_title, customer.name || to_string(customer.email))
         |> assign(:locale, Localize.get_locale())
         |> assign(:customer, customer)
         |> assign(:orders_query, Ash.Query.filter(Order, user_id == ^customer.id))}

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
      <.admin_page width="wide">
        <.admin_page_header
          title={@customer.name || ~t"Unnamed customer"}
          back={~p"/admin/customers"}
          back_label={~t"Customers"}
        >
          <:subtitle>
            <a
              href={fastmail_search_url(@customer.email)}
              target="_blank"
              rel="noopener"
              class="link link-primary inline-flex items-center gap-1.5"
              title={~t"Search Fastmail for this address"}
            >
              <.icon name="hero-envelope" class="h-3.5 w-3.5 shrink-0" />
              <span class="break-all">{@customer.email}</span>
            </a>
          </:subtitle>
        </.admin_page_header>

        <section
          id="customer-summary"
          class="bg-base-100 border-base-content/12 mb-6 grid grid-cols-2 gap-x-8 gap-y-5 border p-4 sm:grid-cols-4 sm:p-5"
        >
          <.summary_fact label={~t"Orders"}>
            <span class="tabular-nums">{@customer.placed_order_count}</span>
          </.summary_fact>
          <.summary_fact label={~t"Total spent"}>
            <span class="tabular-nums">{Format.currency(@customer.total_spent, @locale)}</span>
          </.summary_fact>
          <.summary_fact label={~t"Last order"}>
            <span class="tabular-nums">{Format.date(@customer.last_ordered_at, @locale)}</span>
          </.summary_fact>
          <.summary_fact label={~t"Newsletter"}>
            {if @customer.newsletter_opt_in, do: ~t"Subscribed", else: ~t"Not subscribed"}
          </.summary_fact>
        </section>

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
              class="whitespace-nowrap font-medium tabular-nums hover:underline"
            >
              {Format.date(order.ordered_at, @locale)}
            </.link>
            <div class="text-base-content/65 mt-0.5 text-sm tabular-nums">{order.order_reference}</div>
          </:col>
          <:col :let={order} field="fulfillment_date" sort label={~t"Fulfillment date"} class="max-sm:hidden">
            <span class="whitespace-nowrap tabular-nums">
              {Format.date(order.fulfillment_date, @locale)}
            </span>
          </:col>
          <:col :let={order} field="fulfillment_status" label={~t"Fulfillment"}>
            <.fulfillment_status_badge status={order.fulfillment_status} />
          </:col>
          <:col :let={order} field="payment_status" label={~t"Payment"}>
            <.payment_status_badge status={shown_payment_status(order)} />
          </:col>
          <:col :let={order} field="grand_total" label={~t"Total"}>
            <span class="whitespace-nowrap tabular-nums">
              {Format.currency(order.grand_total, @locale)}
            </span>
          </:col>
          <:col :let={order} field="fulfillment_method" label={~t"Method"} class="max-sm:hidden">
            <.fulfillment_method method={order.fulfillment_method} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp fastmail_search_url(email) do
    "https://app.fastmail.com/mail/search:#{URI.encode_www_form(to_string(email))}"
  end
end

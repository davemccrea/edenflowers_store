defmodule EdenflowersWeb.Admin.CustomersLive do
  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Accounts.User
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Customers")
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
        <.admin_page_header title={~t"Customers"} />

        <Cinder.collection
          id="customers-table"
          resource={User}
          action={:admin_list}
          actor={@current_user}
          search={[
            label: ~t"Customer",
            placeholder: ~t"Search name or email…",
            fn: &search_customers/3
          ]}
          url_state={@url_state}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn customer -> JS.navigate(~p"/admin/customers/#{customer.id}") end}
        >
          <:col :let={customer} field="name" search sort label={~t"Customer"}>
            <.link
              navigate={~p"/admin/customers/#{customer.id}"}
              class="max-w-28 inline-block truncate align-middle font-medium hover:underline sm:max-w-none"
            >
              {customer.name || ~t"Unnamed customer"}
            </.link>
          </:col>
          <:col :let={customer} field="email" label={~t"Email"} class="max-sm:hidden">
            <span class="text-base-content/65">{customer.email}</span>
          </:col>
          <:col :let={customer} field="placed_order_count" sort label={~t"Orders"} class="text-right">
            <span class="tabular-nums">{customer.placed_order_count}</span>
          </:col>
          <:col :let={customer} field="total_spent" sort label={~t"Total spent"} class="text-right max-sm:hidden">
            <span class="whitespace-nowrap tabular-nums">
              {Format.currency(customer.total_spent, @locale)}
            </span>
          </:col>
          <:col
            :let={customer}
            field="last_ordered_at"
            sort={[cycle: [:desc, :asc]]}
            label={~t"Last order"}
            class="max-sm:hidden"
          >
            <span :if={customer.last_ordered_at} class="whitespace-nowrap tabular-nums">
              {Format.date(customer.last_ordered_at, @locale)}
            </span>
            <.blank :if={is_nil(customer.last_ordered_at)} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp search_customers(query, _searchable_columns, search_term) do
    require Ash.Query
    import Ash.Expr

    case_insensitive_term = Ash.CiString.new(search_term)

    Ash.Query.filter(
      query,
      expr(contains(name, ^case_insensitive_term) or contains(email, ^case_insensitive_term))
    )
  end
end

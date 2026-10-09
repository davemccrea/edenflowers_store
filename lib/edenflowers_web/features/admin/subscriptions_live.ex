defmodule EdenflowersWeb.Admin.SubscriptionsLive do
  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias EdenflowersWeb.Admin.DefaultTableView
  alias EdenflowersWeb.Checkout.Fields
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Subscriptions")
     |> assign(:locale, Localize.get_locale())}
  end

  # The subscriptions still being delivered, or about to be once their payment is fixed.
  @default_view %{"state" => "active,payment_failed"}

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, DefaultTableView.handle_params(params, uri, socket, @default_view)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="full">
        <.admin_page_header title={~t"Subscriptions"} />

        <Cinder.collection
          id="subscriptions-table"
          resource={Subscription}
          action={:admin_list}
          actor={@current_user}
          search={[
            label: ~t"Subscription",
            placeholder: ~t"Search name or email…",
            fn: &search_subscriptions/3
          ]}
          url_state={@url_state}
          show_filters={:toggle}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn subscription -> JS.navigate(~p"/admin/subscriptions/#{subscription.id}") end}
        >
          <:col :let={subscription} field="user.name" search sort label={~t"Customer"}>
            <.link
              navigate={~p"/admin/subscriptions/#{subscription.id}"}
              class="max-w-28 inline-block truncate align-middle font-medium hover:underline sm:max-w-none"
            >
              {subscription.user.name || ~t"Unnamed customer"}
            </.link>
          </:col>
          <:col :let={subscription} field="user.email" label={~t"Email"} class="max-sm:hidden">
            <span class="text-base-content/65">{subscription.user.email}</span>
          </:col>
          <:col :let={subscription} field="product_variant.size" sort label={~t"Size"} class="max-sm:hidden">
            {variant_size_label(subscription.product_variant.size)}
          </:col>
          <:col :let={subscription} field="interval_weeks" sort label={~t"Interval"} class="max-sm:hidden">
            {Fields.interval_label(subscription.interval_weeks)}
          </:col>
          <:col :let={subscription} field="next_fulfillment_date" sort={[cycle: [:asc, :desc]]} label={~t"Next delivery"}>
            <span class="tabular-nums max-sm:hidden">{Format.date(subscription.next_fulfillment_date, @locale)}</span>
            <span class="sm:hidden">{Format.day_month(subscription.next_fulfillment_date, @locale)}</span>
          </:col>
          <:col
            :let={subscription}
            field="state"
            sort
            filter={[type: :multi_select, label: ~t"Status", prompt: ~t"All", options: state_options()]}
            label={~t"Status"}
          >
            <.subscription_state_badge state={subscription.state} />
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp state_options do
    Enum.map([:active, :paused, :payment_failed, :cancelled], &{subscription_state_label(&1), &1})
  end

  defp search_subscriptions(query, _searchable_columns, search_term) do
    require Ash.Query
    import Ash.Expr

    case_insensitive_term = Ash.CiString.new(search_term)

    Ash.Query.filter(
      query,
      expr(contains(user.name, ^case_insensitive_term) or contains(user.email, ^case_insensitive_term))
    )
  end
end

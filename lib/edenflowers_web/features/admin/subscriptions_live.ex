defmodule EdenflowersWeb.Admin.SubscriptionsLive do
  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
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

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}
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
            <.link navigate={~p"/admin/subscriptions/#{subscription.id}"} class="font-medium hover:underline">
              {subscription.user.name || ~t"Unnamed customer"}
            </.link>
            <div class="text-base-content/65 mt-0.5 break-all text-sm">{subscription.user.email}</div>
          </:col>
          <:col :let={subscription} field="product_variant.size" sort label={~t"Size"}>
            {variant_size_label(subscription.product_variant.size)}
          </:col>
          <:col :let={subscription} field="interval_weeks" sort label={~t"Interval"}>
            {Fields.interval_label(subscription.interval_weeks)}
          </:col>
          <:col :let={subscription} field="next_fulfillment_date" sort={[cycle: [:asc, :desc]]} label={~t"Next delivery"}>
            <span class="whitespace-nowrap tabular-nums">{Format.date(subscription.next_fulfillment_date, @locale)}</span>
          </:col>
          <:col
            :let={subscription}
            field="state"
            sort
            filter={[type: :select, label: ~t"Status", prompt: ~t"All", options: state_options()]}
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

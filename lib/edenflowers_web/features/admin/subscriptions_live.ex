defmodule EdenflowersWeb.Admin.SubscriptionsLive do
  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias EdenflowersWeb.Checkout.Fields
  alias Edenflowers.Orders
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
          url_state={@url_state}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
        >
          <:col :let={subscription} label={~t"Customer"}>
            <.link navigate={~p"/admin/customers/#{subscription.user_id}"} class="font-medium hover:underline">
              {subscription.user.name || ~t"Unnamed customer"}
            </.link>
            <div class="text-base-content/65 mt-0.5 break-all text-sm">{subscription.user.email}</div>
          </:col>
          <:col :let={subscription} label={~t"Size"}>
            {variant_size_label(subscription.product_variant.size)}
          </:col>
          <:col :let={subscription} field="interval_weeks" sort label={~t"Interval"}>
            {Fields.interval_label(subscription.interval_weeks)}
          </:col>
          <:col :let={subscription} field="next_fulfillment_date" sort label={~t"Next delivery"}>
            <span class="whitespace-nowrap tabular-nums">{Format.date(subscription.next_fulfillment_date, @locale)}</span>
          </:col>
          <:col :let={subscription} field="state" sort label={~t"Status"}>
            <.badge tone={state_tone(subscription.state)}>{state_label(subscription.state)}</.badge>
          </:col>
          <:col :let={subscription} label={~t"Actions"}>
            <div class="flex flex-wrap gap-1">
              <.button
                :if={subscription.state == :active}
                type="button"
                phx-click="pause"
                phx-value-id={subscription.id}
                variant="ghost"
                size="sm"
              >
                {~t"Pause"}
              </.button>
              <.button
                :if={subscription.state == :paused}
                type="button"
                phx-click="resume"
                phx-value-id={subscription.id}
                variant="ghost"
                size="sm"
              >
                {~t"Resume"}
              </.button>
              <.button
                :if={subscription.state != :cancelled}
                type="button"
                phx-click="cancel"
                phx-value-id={subscription.id}
                data-confirm={~t"Cancel this subscription? This can't be undone."}
                variant="ghost"
                size="sm"
                class="text-error"
              >
                {~t"Cancel"}
              </.button>
            </div>
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("pause", %{"id" => id}, socket) do
    {:noreply, change_subscription(socket, id, &Orders.pause_subscription/2, ~t"Subscription paused.")}
  end

  def handle_event("resume", %{"id" => id}, socket) do
    {:noreply, change_subscription(socket, id, &Orders.resume_subscription/2, ~t"Subscription resumed.")}
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    {:noreply, change_subscription(socket, id, &Orders.cancel_subscription/2, ~t"Subscription cancelled.")}
  end

  defp change_subscription(socket, id, action, success_message) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, subscription} <- Orders.get_subscription(id, actor: actor),
           {:ok, _} <- action.(subscription, actor: actor) do
        put_flash(socket, :info, success_message)
      else
        _ -> put_flash(socket, :error, ~t"Could not change the subscription.")
      end

    Cinder.refresh_table(socket, "subscriptions-table")
  end

  defp state_label(:active), do: ~t"Active"
  defp state_label(:paused), do: ~t"Paused"
  defp state_label(:payment_failed), do: ~t"Payment failed"
  defp state_label(:cancelled), do: ~t"Cancelled"

  defp state_tone(:active), do: :success
  defp state_tone(:payment_failed), do: :error
  defp state_tone(_), do: :neutral
end

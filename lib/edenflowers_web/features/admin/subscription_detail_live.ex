defmodule EdenflowersWeb.Admin.SubscriptionDetailLive do
  @moduledoc """
  Admin view of a subscription and its occurrences, with pause, resume, and cancel controls.
  """

  use EdenflowersWeb, :live_view

  require Ash.Query

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Email.Preview
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Translations
  alias EdenflowersWeb.Admin.SubscriptionLog
  alias EdenflowersWeb.Checkout.Fields
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case get_subscription(id, socket.assigns.current_user) do
      {:ok, subscription} ->
        if connected?(socket) do
          EdenflowersWeb.Endpoint.subscribe("admin:subscriptions")
          EdenflowersWeb.Endpoint.subscribe("admin:orders")
        end

        {:ok,
         socket
         |> assign(:page_title, subscription.user.name || to_string(subscription.user.email))
         |> assign(:locale, Localize.get_locale())
         |> assign_subscription(subscription)
         |> assign(cancel_form: nil, preview: nil)
         |> assign(:orders_query, Ash.Query.filter(Order, subscription_id == ^subscription.id))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Subscription not found.")
         |> push_navigate(to: ~p"/admin/subscriptions")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header
          title={@subscription.user.name || ~t"Unnamed customer"}
          back={{~t"Subscriptions", ~p"/admin/subscriptions"}}
        >
          <:subtitle>
            <span class="flex flex-col gap-2.5">
              <span class="inline-flex flex-wrap items-center gap-x-2">
                <span>{product_name(@subscription)}, {variant_size_label(@subscription.product_variant.size)}</span>
                <span aria-hidden="true">·</span>
                <span>{Fields.interval_label(@subscription.interval_weeks)}</span>
              </span>
              <span id="subscription-status" class="inline-flex flex-wrap items-center gap-1.5">
                <.subscription_state_badge state={@subscription.state} />
              </span>
            </span>
          </:subtitle>
          <:actions>
            <.button
              :if={@subscription.pausable?}
              type="button"
              phx-click="pause"
              variant="secondary"
              size="sm"
            >
              {~t"Pause"}
            </.button>
            <.button
              :if={@subscription.resumable?}
              type="button"
              phx-click="resume"
              variant="secondary"
              size="sm"
            >
              {~t"Resume"}
            </.button>
          </:actions>
          <:menu>
            <.actions_menu :if={@subscription.cancellable?} id="subscription-actions">
              <.actions_menu_button
                menu="subscription-actions"
                phx-click="open_cancel"
                class="text-error"
              >
                {~t"Cancel subscription"}
              </.actions_menu_button>
            </.actions_menu>
          </:menu>
        </.admin_page_header>

        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <div class="flex min-w-0 flex-col gap-6">
            <.widget id="subscription-fulfillment" title={~t"Fulfillment"}>
              <div class="grid grid-cols-1 gap-x-8 gap-y-5 sm:grid-cols-3">
                <.summary_fact label={~t"Next delivery"}>
                  <%!-- Only an active subscription makes orders; resuming works out a fresh date. --%>
                  <span :if={@subscription.next_delivery_date} class="tabular-nums">
                    {Format.weekday_day_month(@subscription.next_delivery_date, @locale)}
                  </span>
                  <.blank :if={!@subscription.next_delivery_date} />
                </.summary_fact>
                <.summary_fact label={~t"Method"}>
                  <.fulfillment_method
                    method={@subscription.fulfillment_option.fulfillment_method}
                    label={Translations.translate(@subscription.fulfillment_option).name}
                    class="whitespace-normal"
                  />
                </.summary_fact>
                <.summary_fact :if={@subscription.delivery_address} label={~t"Deliver to"}>
                  {@subscription.delivery_address}
                </.summary_fact>
              </div>

              <div
                :if={@subscription.delivery_instructions}
                class="bg-warning/15 border-base-content/12 mt-5 flex gap-2.5 border px-3 py-2.5"
              >
                <.icon name="hero-information-circle" class="text-warning-content mt-0.5 h-5 w-5 shrink-0" />
                <div>
                  <p class="text-warning-content text-sm font-semibold">{~t"Delivery instructions"}</p>
                  <p class="text-base-content mt-0.5 whitespace-pre-wrap break-words">
                    {@subscription.delivery_instructions}
                  </p>
                </div>
              </div>
            </.widget>

            <section>
              <h2 class="text-base-content mb-4 text-base font-semibold">{~t"Orders"}</h2>

              <Cinder.collection
                id="subscription-orders-table"
                query={@orders_query}
                action={:admin_list}
                actor={@current_user}
                sort_mode="exclusive"
                page_size={[default: 25, options: [10, 25, 50, 100]]}
                theme={EdenflowersWeb.Admin.CinderTheme}
                click={fn order -> JS.navigate(~p"/admin/orders/#{order.id}") end}
              >
                <:col :let={order} field="fulfillment_date" sort={[cycle: [:desc, :asc]]} label={~t"Fulfillment date"}>
                  <.link
                    navigate={~p"/admin/orders/#{order.id}"}
                    class="touch-target whitespace-nowrap font-medium tabular-nums hover:underline"
                  >
                    {Format.date(order.fulfillment_date, @locale)}
                  </.link>
                </:col>
                <:col :let={order} label={~t"Reference"} class="max-sm:hidden">
                  <span class="text-base-content/75 tabular-nums">{order.order_reference}</span>
                </:col>
                <:col :let={order} field="fulfillment_status" sort label={~t"Fulfillment"}>
                  <.fulfillment_status_badge status={order.fulfillment_status} />
                </:col>
                <:col :let={order} field="payment_status" sort label={~t"Payment"} class="max-sm:hidden">
                  <.order_payment_badge order={order} locale={@locale} />
                </:col>
                <:col :let={order} field="grand_total" sort label={~t"Total"} class="text-right">
                  <span class="whitespace-nowrap tabular-nums">{Format.currency(order.grand_total, @locale)}</span>
                </:col>
              </Cinder.collection>
            </section>
          </div>

          <aside class="flex flex-col gap-6">
            <.widget id="subscription-customer" title={~t"Customer"}>
              <.person_block>
                <:contact>
                  <.email_link email={@subscription.user.email} />
                </:contact>
                <:contact>
                  <.link
                    id="subscription-customer-link"
                    navigate={~p"/admin/customers/#{@subscription.user_id}"}
                    class="link link-primary touch-target inline-flex items-center gap-1.5"
                  >
                    <.icon name="hero-user" class="h-3.5 w-3.5 shrink-0" />
                    {~t"View customer's orders"}
                  </.link>
                </:contact>
              </.person_block>
            </.widget>

            <.widget :if={@subscription.recipient_name} id="subscription-recipient" title={~t"Recipient"}>
              <.person_block name={@subscription.recipient_name}>
                <:contact :if={@subscription.recipient_phone_number}>
                  <.phone_link phone_number={@subscription.recipient_phone_number} />
                </:contact>
              </.person_block>
            </.widget>

            <.widget id="subscription-card" title={~t"Card on file"}>
              <p :if={@subscription.card_brand} class="text-sm"><Fields.saved_card card={@subscription} /></p>
              <.blank :if={is_nil(@subscription.card_brand)} />
            </.widget>

            <.widget id="subscription-log" title={~t"History"}>
              <ol :if={@log != []} class="divide-base-content/12 divide-y text-sm">
                <.history_entry
                  :for={{entry, index} <- Enum.with_index(@log)}
                  id={"subscription-log-entry-#{index}"}
                  title={entry.title}
                  at={entry.at}
                  locale={@locale}
                >
                  <:details :if={entry.details != []}>
                    <dl class="border-base-content/12 mt-1.5 mb-1 ml-0.5 space-y-2 border-l pl-3">
                      <div :for={{label, value} <- entry.details}>
                        <dt class="text-base-content/75 text-xs">{label}</dt>
                        <dd class="text-base-content/85 break-words">{value}</dd>
                      </div>
                    </dl>
                  </:details>
                </.history_entry>
              </ol>
              <.blank :if={@log == []} />
            </.widget>
          </aside>
        </div>
      </.admin_page>

      <.admin_drawer id="cancel-subscription" title={~t"Cancel subscription"} on_close={JS.push("close_cancel")}>
        <.form
          :if={@cancel_form}
          for={@cancel_form}
          id="cancel-subscription-form"
          phx-change="validate_cancel"
          phx-submit="cancel"
          class="flex min-h-0 flex-1 flex-col"
        >
          <.drawer_body>
            <p class="text-base-content/75 text-sm">{~t"No more orders are made or charged. This can't be undone."}</p>
            <.customer_email
              id="cancel-subscription-email"
              send={@cancel_form[:email_customer]}
              label={~t"Email the customer"}
              message={@cancel_form[:message]}
              to={to_string(@subscription.user.email)}
              preview={@preview}
              in_swedish={@subscription.locale != "sv-FI" && @cancel_form[:in_swedish]}
            />
          </.drawer_body>
          <.drawer_footer>
            <.button type="submit" variant="destructive">{~t"Cancel subscription"}</.button>
            <.button
              type="button"
              phx-click={JS.exec("phx-hide", to: "#cancel-subscription") |> JS.push("close_cancel")}
              variant="ghost"
            >{~t"Keep subscription"}</.button>
          </.drawer_footer>
        </.form>
      </.admin_drawer>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("pause", _params, socket) do
    {:noreply, change_subscription(socket, &Orders.pause_subscription/2, ~t"Subscription paused.")}
  end

  def handle_event("resume", _params, socket) do
    {:noreply, change_subscription(socket, &Orders.resume_subscription/2, ~t"Subscription resumed.")}
  end

  def handle_event("open_cancel", _params, socket) do
    params = %{"email_customer" => "true", "message" => ""}

    {:noreply,
     socket
     |> assign(:cancel_form, to_form(params, as: :cancel))
     |> assign_preview(params)
     |> push_event("js-exec", %{to: "#cancel-subscription", attr: "phx-show"})}
  end

  def handle_event("close_cancel", _params, socket) do
    {:noreply, assign(socket, cancel_form: nil, preview: nil)}
  end

  def handle_event("validate_cancel", %{"cancel" => params}, socket) do
    {:noreply, socket |> assign(:cancel_form, to_form(params, as: :cancel)) |> assign_preview(params)}
  end

  def handle_event("cancel", %{"cancel" => params}, socket) do
    input = %{email_customer?: params["email_customer"] != "false", message: params["message"]}
    cancel = &Orders.cancel_subscription(&1, input, &2)

    {:noreply,
     socket
     |> change_subscription(cancel, ~t"Subscription cancelled.")
     |> assign(cancel_form: nil, preview: nil)
     |> push_event("js-exec", %{to: "#cancel-subscription", attr: "phx-hide"})}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket) do
    {:ok, subscription} = get_subscription(socket.assigns.subscription.id, socket.assigns.current_user)

    {:noreply,
     socket
     |> assign_subscription(subscription)
     |> Cinder.refresh_table("subscription-orders-table")}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp change_subscription(socket, action, success_message) do
    actor = socket.assigns.current_user

    with {:ok, _} <- action.(socket.assigns.subscription, actor: actor),
         {:ok, subscription} <- get_subscription(socket.assigns.subscription.id, actor) do
      socket
      |> assign_subscription(subscription)
      |> put_flash(:info, success_message)
      |> Cinder.refresh_table("subscription-orders-table")
    else
      _ -> put_flash(socket, :error, ~t"Could not change the subscription.")
    end
  end

  defp assign_preview(socket, params) do
    locale = if params["in_swedish"] == "true", do: "sv-FI"
    preview = Preview.build(:subscription_cancelled, socket.assigns.subscription, %{message: params["message"]}, locale)
    assign(socket, :preview, preview)
  end

  defp get_subscription(id, actor) do
    Orders.get_subscription(id,
      actor: actor,
      load: [
        :user,
        :fulfillment_option,
        :next_delivery_date,
        :pausable?,
        :resumable?,
        :cancellable?,
        paper_trail_versions: [:user],
        product_variant: [product: :product_variants]
      ]
    )
  end

  defp assign_subscription(socket, subscription) do
    sizes = Map.new(subscription.product_variant.product.product_variants, &{&1.id, &1.size})

    socket
    |> assign(:subscription, subscription)
    |> assign(:log, SubscriptionLog.entries(subscription.paper_trail_versions, sizes, socket.assigns.locale))
  end

  defp product_name(subscription), do: Translations.translate(subscription.product_variant.product).name
end

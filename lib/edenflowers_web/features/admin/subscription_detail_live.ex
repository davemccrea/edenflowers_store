defmodule EdenflowersWeb.Admin.SubscriptionDetailLive do
  @moduledoc """
  Admin view of a subscription and its occurrences, with change, pause, resume, and cancel controls.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  require Ash.Query

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.Drawers

  alias Edenflowers.Catalog
  alias Edenflowers.Email.Preview
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Weekday
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Translations
  alias EdenflowersWeb.Admin.Drawers
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
         |> assign(change_form: nil, cancel_form: nil, preview: nil)
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
              :if={@subscription.plan_changeable?}
              type="button"
              phx-click="open_change"
              variant="secondary"
              size="sm"
            >
              {~t"Change"}
            </.button>
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
                    class="touch-target whitespace-nowrap font-semibold tabular-nums hover:underline"
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
                <:contact :if={@subscription.customer_phone_number}>
                  <.phone_link phone_number={@subscription.customer_phone_number} />
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

      <.admin_drawer id="change-subscription" title={~t"Change subscription"} on_close={JS.push("close_change")}>
        <.form
          :if={@change_form}
          for={@change_form}
          id="change-subscription-form"
          phx-change="validate_change"
          phx-submit="change"
          class="flex min-h-0 flex-1 flex-col"
        >
          <.drawer_body>
            <.refusal form={@change_form} />
            <p class="text-base-content/75 text-sm">
              {~t"Applies from the next order not yet made, even past the customer's change deadline."}
            </p>
            <.input
              field={@change_form[:product_variant_id]}
              type="select"
              label={~t"Size"}
              options={@size_options}
              class="select w-full"
            />
            <.input
              field={@change_form[:interval_weeks]}
              type="select"
              label={~t"How often"}
              options={Enum.map(Subscription.intervals(), &{Fields.interval_label(&1), &1})}
              class="select w-full"
            />
            <.input
              field={@change_form[:delivery_day]}
              type="select"
              label={~t"Delivery day"}
              options={@day_options}
              class="select w-full"
            />
          </.drawer_body>
          <.drawer_footer>
            <.button type="submit" variant="primary">{~t"Save changes"}</.button>
            <.button
              type="button"
              phx-click={JS.exec("phx-hide", to: "#change-subscription") |> JS.push("close_change")}
              variant="ghost"
            >{~t"Discard"}</.button>
          </.drawer_footer>
        </.form>
      </.admin_drawer>

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
            <.refusal form={@cancel_form} />
            <p class="text-base-content/75 text-sm">{~t"No more orders are made or charged. This can't be undone."}</p>
            <.customer_email
              id="cancel-subscription-email"
              send={@cancel_form[:email_customer?]}
              label={~t"Email the customer"}
              form={@cancel_form}
              to={to_string(@subscription.user.email)}
              preview={@preview}
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

  def handle_event("open_change", _params, socket) do
    %{subscription: subscription, current_user: actor, locale: locale} = socket.assigns

    form =
      subscription
      |> AshPhoenix.Form.for_update(:change,
        as: "change",
        actor: actor,
        params: %{
          "product_variant_id" => subscription.product_variant_id,
          "interval_weeks" => subscription.interval_weeks,
          "delivery_day" => Weekday.from_date(subscription.next_fulfillment_date)
        }
      )
      |> to_form()

    size_options =
      for variant <- Catalog.list_subscription_sizes!(subscription.product_variant_id) do
        {"#{variant_size_label(variant.size)} · #{Format.currency(variant.price, locale)}", variant.id}
      end

    day_options =
      for day <- Weekday.all(), day in Fulfillment.get_shop_calendar!().available_days do
        {String.capitalize(Format.weekday_name(day, locale)), day}
      end

    {:noreply,
     socket
     |> assign(change_form: form, size_options: size_options, day_options: day_options)
     |> push_event("js-exec", %{to: "#change-subscription", attr: "phx-show"})}
  end

  def handle_event("close_change", _params, socket) do
    {:noreply, assign(socket, :change_form, nil)}
  end

  def handle_event("validate_change", %{"change" => params}, socket) do
    {:noreply, assign(socket, :change_form, AshPhoenix.Form.validate(socket.assigns.change_form, params))}
  end

  def handle_event("change", %{"change" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.change_form, params: params) do
      {:ok, _subscription} ->
        {:ok, subscription} = get_subscription(socket.assigns.subscription.id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign_subscription(subscription)
         |> put_flash(:success, ~t"Subscription changed.")
         |> assign(:change_form, nil)
         |> push_event("js-exec", %{to: "#change-subscription", attr: "phx-hide"})}

      {:error, form} ->
        {:noreply, assign(socket, :change_form, form)}
    end
  end

  def handle_event("open_cancel", _params, socket) do
    form =
      socket.assigns.subscription
      |> AshPhoenix.Form.for_update(:cancel,
        as: "cancel",
        actor: socket.assigns.current_user,
        params: %{"email_customer?" => "true"},
        transform_params: &Drawers.keep_email_edits/3
      )
      |> to_form()

    {:noreply,
     socket
     |> assign(:cancel_form, form)
     |> assign(:preview, Preview.build(:subscription_cancelled, socket.assigns.subscription, %{}))
     |> push_event("js-exec", %{to: "#cancel-subscription", attr: "phx-show"})}
  end

  def handle_event("close_cancel", _params, socket) do
    {:noreply, assign(socket, cancel_form: nil, preview: nil)}
  end

  def handle_event("validate_cancel", %{"cancel" => params}, socket) do
    {:noreply, assign(socket, :cancel_form, AshPhoenix.Form.validate(socket.assigns.cancel_form, params))}
  end

  def handle_event("cancel", %{"cancel" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.cancel_form, params: params) do
      {:ok, _subscription} ->
        {:ok, subscription} = get_subscription(socket.assigns.subscription.id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign_subscription(subscription)
         |> put_flash(:success, ~t"Subscription cancelled.")
         |> Cinder.refresh_table("subscription-orders-table")
         |> assign(cancel_form: nil, preview: nil)
         |> push_event("js-exec", %{to: "#cancel-subscription", attr: "phx-hide"})}

      {:error, form} ->
        {:noreply, assign(socket, :cancel_form, form)}
    end
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
      |> put_flash(:success, success_message)
      |> Cinder.refresh_table("subscription-orders-table")
    else
      _ -> put_flash(socket, :error, ~t"Could not change the subscription.")
    end
  end

  defp get_subscription(id, actor) do
    Orders.get_subscription(id,
      actor: actor,
      load: [
        :user,
        :fulfillment_option,
        :next_delivery_date,
        :plan_changeable?,
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

defmodule EdenflowersWeb.Account.SubscriptionManager do
  @moduledoc """
  One subscription on the account page: its row in the list and the drawer that
  manages it. After a change it sends `:subscriptions_changed` so the page
  reloads its subscriptions, orders and timeline and passes them back in.
  """
  use EdenflowersWeb, :live_component

  require Logger

  alias Edenflowers.Catalog
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment.Weekday
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Translations
  alias EdenflowersWeb.Checkout.Fields

  @impl true
  def mount(socket) do
    {:ok, assign(socket, edited?: false, notice: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    sizes = Catalog.list_subscription_sizes!(socket.assigns.subscription.product_variant_id)

    {:ok, assign(socket, sizes: sizes)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <li id={@id} class="border-base-content/12 border-t py-6">
      <div class="grid-cols-[1fr_auto] grid items-baseline gap-x-4">
        <h3 id={"#{@id}-name"} class="card-heading text-balance">
          {subscription_name(@subscription)}
        </h3>
        <p class="font-serif text-xl tabular-nums">
          {Format.storefront_price(@subscription.product_variant.price, @locale)}
        </p>
        <p class="text-base-content/70 mt-1 text-sm">{plan_label(@subscription)}</p>
        <p class="text-base-content/70 text-right text-sm">{~t"per delivery"}</p>
      </div>

      <div class="mt-5 flex items-end justify-between gap-4">
        <div data-testid="subscription-status">
          <p class="eyebrow text-base-content/70 mb-2">
            {if @subscription.state == :active, do: ~t"Next delivery", else: ~t"Status"}
          </p>
          <.next_delivery subscription={@subscription} locale={@locale} />
        </div>
        <.manage_button subscription={@subscription} />
      </div>

      <.manage_drawer
        subscription={@subscription}
        locale={@locale}
        open_days={@open_days}
        sizes={@sizes}
        edited?={@edited?}
        notice={@notice}
        target={@myself}
      />
    </li>
    """
  end

  @impl true
  def handle_event("pause_subscription", _params, socket) do
    {:noreply, change_subscription(socket, :status, &Orders.pause_subscription/2, nil)}
  end

  def handle_event("resume_subscription", _params, socket) do
    {:noreply, change_subscription(socket, :status, &Orders.resume_subscription/2, nil)}
  end

  def handle_event("cancel_subscription", _params, socket) do
    socket = change_subscription(socket, :status, &Orders.cancel_subscription/2, fn _ -> ~t"Subscription cancelled" end)

    # The card leaves the page once nothing is left to deliver, so the page says it instead.
    # A component's own flash only reaches the page on a redirect.
    case socket.assigns.notice do
      {:status, :info, message} ->
        send(self(), {:put_flash, :success, message})
        {:noreply, assign(socket, notice: nil)}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_subscription", params, socket) do
    subscription = socket.assigns.subscription

    edited? =
      params["product_variant_id"] != subscription.product_variant_id or
        params["interval_weeks"] != to_string(subscription.interval_weeks) or
        params["delivery_day"] != to_string(delivery_day(subscription))

    {:noreply, assign(socket, edited?: edited?)}
  end

  def handle_event("change_subscription", params, socket) do
    changes = Map.take(params, ["product_variant_id", "interval_weeks", "delivery_day"])
    change = &Orders.change_subscription(&1, changes, Keyword.put(&2, :load, :product_variant))

    socket =
      socket
      |> change_subscription(:plan, change, &change_confirmation(&1, socket.assigns.locale))
      |> assign(edited?: false)

    {:noreply, socket}
  end

  def subscription_name(subscription), do: Translations.translate(subscription.product_variant.product).name

  # The outcome shows inside the subscription's drawer, which sits above the
  # page's flash while it's open, in the row whose action caused it. Pause and
  # resume pass no success message: the status line and button already show it.
  # The subscription is read again so the change is checked against what's
  # saved, not what the page last showed.
  defp change_subscription(socket, row, action, success_message) do
    %{subscription: subscription, current_user: user} = socket.assigns

    socket =
      case Orders.get_subscription(subscription.id, actor: user) do
        {:ok, subscription} ->
          case action.(subscription, actor: user) do
            {:ok, subscription} ->
              assign(socket, notice: success_message && {row, :info, success_message.(subscription)})

            {:error, error} ->
              Logger.info("Subscription change refused: #{inspect(error)}")
              assign(socket, notice: {row, :error, subscription_error_message(error)})
          end

        {:error, error} ->
          Logger.info("Subscription change refused: #{inspect(error)}")
          put_flash(socket, :error, subscription_error_message(error))
      end

    send(self(), :subscriptions_changed)
    socket
  end

  # The cutoff's own message says why; anything else means the page was stale.
  defp subscription_error_message(%Ash.Error.Invalid{errors: errors}) do
    Enum.find_value(errors, ~t"Your subscription couldn't be changed.", fn
      %Ash.Error.Changes.InvalidAttribute{field: :next_fulfillment_date, message: message} -> message
      _ -> nil
    end)
  end

  defp subscription_error_message(_error), do: ~t"Your subscription couldn't be changed."

  defp size_options(sizes, locale) do
    for variant <- sizes do
      {"#{variant_size_label(variant.size)} · #{Format.storefront_price(variant.price, locale)}", variant.id}
    end
  end

  defp delivery_day(subscription), do: Weekday.from_date(subscription.next_fulfillment_date)

  defp delivery_day_options(open_days, locale) do
    for day <- Weekday.all(), day in open_days do
      {String.capitalize(Format.weekday_name(day, locale)), day}
    end
  end

  # The occurrence job reads the subscription when it books each delivery, so a
  # change applies from the first one it hasn't booked.
  defp change_confirmation(subscription, locale) do
    %{product_variant: variant, interval_weeks: weeks} = subscription
    from = Format.weekday_date(subscription.next_fulfillment_date, locale)
    size = variant_size_label(variant.size)
    price = Format.storefront_price(variant.price, locale)

    ~t"From #{date = from}: #{size = size}, #{interval = String.downcase(Fields.interval_label(weeks))}, #{price = price} per delivery."
  end

  attr :subscription, :map, required: true
  attr :booked, :map, default: nil
  attr :locale, :string, required: true
  attr :target, :any, required: true

  # Asked in place rather than in a dialog, since the drawer is already a layer
  # of its own.
  defp cancel_confirmation(assigns) do
    assigns = assign(assigns, id: assigns.subscription.id, final_delivery?: final_delivery?(assigns.booked))

    ~H"""
    <section
      id={"cancel-subscription-#{@id}"}
      class="bg-cream text-cream-content mt-4 hidden p-5"
      aria-labelledby={"cancel-subscription-#{@id}-title"}
    >
      <h3 id={"cancel-subscription-#{@id}-title"} tabindex="-1" class="card-heading outline-hidden">
        {~t"Stop your subscription?"}
      </h3>
      <p :if={@final_delivery?} class="mt-2 text-sm" data-testid="final-delivery-warning">
        {~t"Your delivery on #{date = Format.weekday_date(@booked.fulfillment_date, @locale)} is already being prepared and will be your final delivery. There will be no deliveries or charges after that."}
      </p>
      <p :if={not @final_delivery?} class="mt-2 text-sm">{~t"There will be no more deliveries or charges."}</p>
      <p :if={@subscription.state == :active} class="mt-2 text-sm">
        {~t"Want a break instead?"}
        <.button
          type="button"
          variant="text"
          phx-click={JS.push("pause_subscription", target: @target) |> hide_cancel_confirmation(@id)}
        >
          {~t"Pause it"}
        </.button>
      </p>
      <div class="mt-5 flex flex-wrap gap-3">
        <.button type="button" variant="primary" phx-click={hide_cancel_confirmation(@id)}>
          {~t"Keep it"}
        </.button>
        <.button type="button" variant="destructive" phx-click={JS.push("cancel_subscription", target: @target)}>
          {~t"Stop subscription"}
        </.button>
      </div>
    </section>
    """
  end

  defp show_cancel_confirmation(id) do
    JS.hide(to: "#subscription-#{id}-actions")
    |> JS.show(to: "#cancel-subscription-#{id}")
    |> JS.focus(to: "#cancel-subscription-#{id}-title")
  end

  defp hide_cancel_confirmation(js \\ %JS{}, id) do
    js
    |> JS.hide(to: "#cancel-subscription-#{id}")
    |> JS.show(to: "#subscription-#{id}-actions", display: "flex")
    |> JS.focus(to: "#cancel-subscription-#{id}-open")
  end

  attr :subscription, :map, required: true
  attr :unpaid, :map, default: nil
  attr :locale, :string, required: true

  # Saving a new card restarts a held subscription and paying the link restarts
  # it too, but neither does the other's job, so a held row asks for both.
  defp subscription_payment(assigns) do
    assigns = assign(assigns, held?: assigns.subscription.state == :payment_failed)

    ~H"""
    <div :if={@held? or @unpaid} class="flex flex-col gap-3" data-testid="subscription-payment">
      <div>
        <p class="font-medium">
          <%= cond do %>
            <% @held? and @unpaid -> %>
              {~t"We couldn't charge your card for #{date = Format.weekday_date(@unpaid.fulfillment_date, @locale)} (#{amount = Format.currency(@unpaid.grand_total, @locale)})."}
            <% @held? -> %>
              {~t"Your subscription is on hold because a payment didn't go through."}
            <% true -> %>
              {~t"Your delivery on #{date = Format.weekday_date(@unpaid.fulfillment_date, @locale)} (#{amount = Format.currency(@unpaid.grand_total, @locale)}) is still unpaid."}
          <% end %>
        </p>
        <p :if={@held?} class="text-base-content/70 text-sm">
          {~t"Update your card to restart your subscription."}
          <span :if={@unpaid}>{~t"A new card doesn't pay for this delivery, so pay for it separately."}</span>
        </p>
      </div>
      <div class="flex flex-wrap gap-3">
        <.button
          :if={@held?}
          navigate={~p"/account/subscriptions/#{@subscription.id}/card"}
          variant="primary"
          data-testid="subscription-update-card"
        >
          {~t"Update card"}
        </.button>
        <.button
          :if={@unpaid}
          navigate={~p"/pay/orders/#{@unpaid.payment_link_token}"}
          variant={if @held?, do: "secondary", else: "primary"}
          data-testid="subscription-pay-now"
        >
          {~t"Pay #{amount = Format.currency(@unpaid.grand_total, @locale)} now"}
        </.button>
      </div>
    </div>
    """
  end

  defp plan_label(%{product_variant: variant, interval_weeks: weeks}) do
    "#{variant_size_label(variant.size)} · #{Fields.interval_label(weeks)}"
  end

  defp final_delivery?(nil), do: false
  defp final_delivery?(order), do: not order.changes_open?

  attr :subscription, :map, required: true

  defp manage_button(assigns) do
    ~H"""
    <.button
      type="button"
      variant="secondary"
      size="sm"
      class="whitespace-nowrap"
      aria-label={~t"Manage #{name = subscription_name(@subscription)}"}
      phx-click={JS.exec("phx-show", to: "#manage-subscription-#{@subscription.id}")}
    >
      {~t"Manage"}
    </.button>
    """
  end

  attr :subscription, :map, required: true
  attr :locale, :string, required: true

  # The list's short form: the date, then one line on what's happening.
  defp next_delivery(%{subscription: %{state: :payment_failed}} = assigns) do
    assigns = assign(assigns, unpaid: assigns.subscription.unpaid_occurrence)

    ~H"""
    <span class="text-error font-medium">{~t"Payment failed"}</span>
    <span class="block text-sm">
      <.link
        :if={@unpaid}
        navigate={~p"/pay/orders/#{@unpaid.payment_link_token}"}
        class="link-underline-hover text-primary"
        data-testid="subscription-pay-now"
      >
        {~t"Pay #{amount = Format.currency(@unpaid.grand_total, @locale)} now"}
      </.link>
      <span :if={@unpaid}>·</span>
      <.link
        navigate={~p"/account/subscriptions/#{@subscription.id}/card"}
        class="link-underline-hover text-primary"
        data-testid="subscription-update-card"
      >
        {~t"Update card"}
      </.link>
    </span>
    """
  end

  # Pausing leaves a delivery already being prepared in place.
  defp next_delivery(%{subscription: %{state: :paused}} = assigns) do
    assigns = assign(assigns, booked: assigns.subscription.booked_occurrence)

    ~H"""
    {~t"Paused"}
    <span :if={@booked} class="text-base-content/70 block text-sm">
      {~t"After #{date = Format.day_month(@booked.fulfillment_date, @locale)}"}
    </span>
    <span :if={!@booked} class="text-base-content/70 block text-sm">{~t"No deliveries or charges"}</span>
    """
  end

  defp next_delivery(%{subscription: %{state: :cancelled}} = assigns) do
    assigns = assign(assigns, booked: assigns.subscription.booked_occurrence)

    ~H"""
    <span class="font-medium tabular-nums">{Format.weekday_day_month(@booked.fulfillment_date, @locale)}</span>
    <span class="text-base-content/70 block text-sm">{~t"One final delivery remains"}</span>
    """
  end

  defp next_delivery(assigns) do
    %{subscription: subscription} = assigns

    assigns =
      assign(assigns,
        booked: subscription.booked_occurrence,
        unpaid: subscription.unpaid_occurrence,
        next: subscription.next_fulfillment_date
      )

    ~H"""
    <span class="tabular-nums">
      {Format.weekday_day_month(if(@booked, do: @booked.fulfillment_date, else: @next), @locale)}
    </span>
    <span :if={@unpaid} class="text-base-content/70 block text-sm">
      <span class="text-error">{~t"Unpaid"}</span>
      ·
      <.link navigate={~p"/pay/orders/#{@unpaid.payment_link_token}"} class="link-underline-hover text-primary">
        {~t"Pay now"}
      </.link>
    </span>
    <span :if={!@unpaid and !@booked} class="text-base-content/70 block text-sm">
      {~t"Charged #{date = Format.day_month(@subscription.charged_on, @locale)}"}
    </span>
    """
  end

  attr :subscription, :map, required: true
  attr :locale, :string, required: true
  attr :open_days, :list, required: true
  attr :sizes, :list, required: true
  attr :edited?, :boolean, required: true
  attr :notice, :any, default: nil
  attr :target, :any, required: true

  defp manage_drawer(assigns) do
    %{subscription: subscription} = assigns

    assigns =
      assign(assigns,
        id: subscription.id,
        unpaid: subscription.unpaid_occurrence,
        booked: subscription.booked_occurrence
      )

    ~H"""
    <.drawer
      id={"manage-subscription-#{@id}"}
      placement="right"
      label={subscription_name(@subscription)}
      class="bg-base-100 border-l-1 w-[88vw] flex h-full flex-col sm:w-[28rem]"
    >
      <header class="flex flex-row items-start justify-between gap-4 pt-6 pr-4 pl-4 sm:pt-8 sm:pl-8">
        <h2 class="section-title">{subscription_name(@subscription)}</h2>
        <.icon_button
          aria_label={~t"Close"}
          phx-click={JS.exec("phx-hide", to: "#manage-subscription-#{@id}")}
        >
          <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
        </.icon_button>
      </header>

      <div class="flex flex-1 flex-col gap-6 overflow-y-auto overscroll-contain p-4 sm:p-8">
        <.subscription_payment subscription={@subscription} unpaid={@unpaid} locale={@locale} />

        <dl class="border-base-content/12 border-t">
          <.detail_row label={if @subscription.state == :active, do: ~t"Next delivery", else: ~t"Status"}>
            <div data-testid="subscription-drawer-status">
              <.drawer_status subscription={@subscription} booked={@booked} locale={@locale} />
            </div>

            <p :if={@subscription.changes_closed?} class="text-base-content/70 mt-2 text-sm" data-testid="changes-closed">
              {~t"Your next delivery is already being prepared. You can make changes again from #{date = Format.weekday_date(@subscription.changes_reopen_on, @locale)}."}
              <.link navigate={~q"/#{language}/contact"} class="link-underline-hover text-base-content">
                {~t"Need to change this one? Contact us."}
              </.link>
            </p>

            <div
              :if={@subscription.state != :cancelled}
              id={"subscription-#{@id}-actions"}
              role="group"
              aria-label={~t"Deliveries"}
              class="mt-4 flex flex-wrap items-center gap-x-6 gap-y-3"
            >
              <%!-- One id for both, so the button is patched in place and keeps focus. --%>
              <.button
                :if={@subscription.changeable?}
                id={"subscription-#{@id}-pause"}
                type="button"
                variant={if @subscription.state == :paused, do: "primary", else: "secondary"}
                phx-click={if @subscription.state == :active, do: "pause_subscription", else: "resume_subscription"}
                phx-target={@target}
              >
                {if @subscription.state == :active, do: ~t"Pause", else: ~t"Resume"}
              </.button>
              <.button
                id={"cancel-subscription-#{@id}-open"}
                type="button"
                variant="text"
                class="min-h-11"
                aria-controls={"cancel-subscription-#{@id}"}
                phx-click={show_cancel_confirmation(@id)}
              >
                {~t"Cancel subscription"}
              </.button>
            </div>

            <.notice notice={@notice} row={:status} />

            <.cancel_confirmation
              :if={@subscription.state != :cancelled}
              subscription={@subscription}
              booked={@booked}
              locale={@locale}
              target={@target}
            />
          </.detail_row>

          <.detail_row :if={@subscription.state != :cancelled} label={~t"Plan"}>
            <div class="flex items-baseline justify-between gap-4">
              <div>
                <p class="font-serif text-lg">{plan_label(@subscription)}</p>
                <p class="text-base-content/70 text-sm">
                  {~t"#{price = Format.storefront_price(@subscription.product_variant.price, @locale)} per delivery"}
                </p>
              </div>
              <.button
                :if={@subscription.changeable?}
                type="button"
                variant="text"
                class="min-h-11 shrink-0"
                aria-controls={"change-subscription-#{@id}"}
                aria-expanded="false"
                phx-click={
                  JS.toggle(to: "#change-subscription-#{@id}", display: "flex")
                  |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                }
              >
                {~t"Change"}
              </.button>
            </div>
            <form
              :if={@subscription.changeable?}
              id={"change-subscription-#{@id}"}
              phx-change="edit_subscription"
              phx-submit="change_subscription"
              phx-target={@target}
              class="mt-4 hidden flex-col gap-3"
            >
              <.input
                type="select"
                id={"subscription-#{@id}-size"}
                name="product_variant_id"
                label={~t"Size"}
                options={size_options(@sizes, @locale)}
                value={@subscription.product_variant_id}
              />
              <.input
                type="select"
                id={"subscription-#{@id}-interval"}
                name="interval_weeks"
                label={~t"How often"}
                options={Enum.map(Subscription.intervals(), &{Fields.interval_label(&1), &1})}
                value={@subscription.interval_weeks}
              />
              <.input
                type="select"
                id={"subscription-#{@id}-day"}
                name="delivery_day"
                label={~t"Delivery day"}
                options={delivery_day_options(@open_days, @locale)}
                value={delivery_day(@subscription)}
              />
              <.button
                type="submit"
                variant="primary"
                class="self-start"
                disabled={not @edited?}
              >
                {~t"Save changes"}
              </.button>
            </form>
            <.notice notice={@notice} row={:plan} />
          </.detail_row>

          <.detail_row :if={@subscription.state != :cancelled and @subscription.delivery_address} label={~t"Delivers to"}>
            <p class="font-serif text-lg" data-testid="subscription-recipient">
              <span :if={@subscription.recipient_name} class="block">{@subscription.recipient_name}</span>
              {@subscription.delivery_address}
            </p>
            <p class="text-base-content/70 mt-1 text-sm">
              <.link navigate={~q"/#{language}/contact"} class="link-underline-hover text-base-content">
                {~t"Contact us to change the address."}
              </.link>
            </p>
          </.detail_row>

          <.detail_row :if={@subscription.state not in [:cancelled, :payment_failed]} label={~t"Card"}>
            <div class="flex items-center justify-between gap-4">
              <p class="font-serif text-lg" data-testid="subscription-card">
                <Fields.saved_card :if={@subscription.card_brand} card={@subscription} />
                <span :if={!@subscription.card_brand}>{~t"Saved card"}</span>
              </p>
              <.link
                navigate={~p"/account/subscriptions/#{@id}/card"}
                class="link-underline-static-body min-h-11 inline-flex shrink-0 items-center hover:decoration-current"
              >
                {~t"Update card"}
              </.link>
            </div>
          </.detail_row>
        </dl>
      </div>
    </.drawer>
    """
  end

  attr :notice, :any, required: true
  attr :row, :atom, required: true

  defp notice(%{notice: {row, kind, message}, row: row} = assigns) do
    assigns = assign(assigns, kind: kind, message: message)

    ~H"""
    <p
      role="status"
      class={["bg-cream mt-4 px-4 py-3 text-sm", if(@kind == :error, do: "text-error", else: "text-cream-content")]}
      data-testid="subscription-notice"
    >
      {@message}
    </p>
    """
  end

  defp notice(assigns), do: ~H""

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class="border-base-content/12 border-b py-5">
      <dt class="eyebrow text-base-content/70 mb-2">{@label}</dt>
      <dd>{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr :subscription, :map, required: true
  attr :booked, :map, default: nil
  attr :locale, :string, required: true

  defp drawer_status(%{subscription: %{state: :active}} = assigns) do
    assigns = assign(assigns, next: assigns.subscription.next_fulfillment_date)

    ~H"""
    <%= if @booked do %>
      <p class="font-serif text-lg">{Format.weekday_date(@booked.fulfillment_date, @locale)}</p>
      <p class="text-base-content/70 text-sm">
        {~t"The one after: #{date = Format.weekday_date(@next, @locale)}, charged on #{charge_date = Format.weekday_date(@subscription.charged_on, @locale)}."}
      </p>
    <% else %>
      <p class="font-serif text-lg">{Format.weekday_date(@next, @locale)}</p>
      <p class="text-base-content/70 text-sm">
        {~t"Charged to your card on #{date = Format.weekday_date(@subscription.charged_on, @locale)}."}
      </p>
    <% end %>
    """
  end

  defp drawer_status(%{subscription: %{state: :paused}} = assigns) do
    ~H"""
    <p class="font-serif text-lg">{~t"Paused"}</p>
    <p class="text-base-content/70 text-sm">
      <span :if={@booked}>
        {~t"Your delivery on #{date = Format.weekday_date(@booked.fulfillment_date, @locale)} will still arrive."}
      </span>
      {~t"Resume now for a delivery on #{date = Format.weekday_date(@subscription.resume_date, @locale)}."}
    </p>
    """
  end

  defp drawer_status(%{subscription: %{state: :payment_failed}} = assigns) do
    ~H"""
    <p class="font-serif text-lg">{~t"On hold"}</p>
    <p class="text-base-content/70 text-sm">{~t"No deliveries until the unpaid one is paid or your card is updated."}</p>
    """
  end

  defp drawer_status(%{subscription: %{state: :cancelled}} = assigns) do
    ~H"""
    <p class="font-serif text-lg">{~t"One final delivery remains"}</p>
    <p class="text-base-content/70 text-sm">
      {~t"Your delivery on #{date = Format.weekday_date(@booked.fulfillment_date, @locale)} was already being prepared when you cancelled. There will be no deliveries or charges after that."}
    </p>
    """
  end
end

defmodule EdenflowersWeb.Account.AccountLive do
  @moduledoc """
  Customer account page for personal details, email changes, newsletter preference, orders, and subscriptions.
  """

  use EdenflowersWeb, :live_view

  require Logger

  alias Edenflowers.Accounts
  alias Edenflowers.Catalog
  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Orders
  alias Edenflowers.ShopTime
  alias Edenflowers.Translations
  alias EdenflowersWeb.Account.SubscriptionManager

  @saved_visible_ms 2500
  @newsletter_form_id "newsletter-preference"
  @past_visible 5

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = Ash.load!(socket.assigns.current_user, :first_name, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(page_title: ~t"Account")
     |> assign(current_user: user)
     |> assign(details_form: details_form(user))
     |> assign(details_saved?: false)
     |> assign(pending_email: nil)
     |> assign(code_form: to_form(%{"code" => ""}, as: :confirm))
     |> assign(locale: Format.locale())
     |> assign(orders: orders(user))
     |> assign(subscriptions: subscriptions(user))
     |> assign(open_days: Fulfillment.get_shop_calendar!().available_days)
     |> assign_subscription_path()
     |> assign(registrations: registrations(user))
     |> assign(past_visible: @past_visible)
     |> assign_timeline()
     |> assign(newsletter_form_id: @newsletter_form_id)
     |> assign(newsletter_saved?: false)
     |> assign(newsletter_saved_token: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      notice_bar={@notice_bar}
    >
      <.container class="max-w-3xl">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-baseline sm:justify-between">
          <h1 class="page-title">
            {if @current_user.first_name, do: ~t"Hi, #{@current_user.first_name}!", else: ~t"Account"}
          </h1>
          <.button href={~p"/sign-out"} method="delete" variant="secondary" size="sm" class="w-fit">
            {~t"Sign out"}
          </.button>
        </div>

        <%!-- Cream marks the one living thing on the page; the rest is history and settings. --%>
        <.account_section
          :if={@subscriptions != []}
          id="subscriptions"
          title={~t"Subscriptions"}
          class="bg-cream text-cream-content -mx-4 mt-12 px-4 pt-10 pb-6 sm:-mx-8 sm:mt-16 sm:px-8"
        >
          <ol class="mt-6" data-testid="subscriptions">
            <.live_component
              :for={subscription <- @subscriptions}
              module={SubscriptionManager}
              id={"subscription-#{subscription.id}"}
              subscription={subscription}
              locale={@locale}
              open_days={@open_days}
              current_user={@current_user}
            />
          </ol>
        </.account_section>

        <.account_section id="upcoming" title={~t"Coming up"}>
          <div :if={@upcoming == []} class="mt-6">
            <p>{~t"Nothing on its way."}</p>
            <div class="mt-4 flex flex-wrap gap-x-6 gap-y-2">
              <.button navigate={~q"/#{language}/store"} variant="text">{~t"Visit the shop"}</.button>
              <.button navigate={~q"/#{language}/courses"} variant="text">{~t"See what's coming up"}</.button>
            </div>
          </div>

          <ol :if={@upcoming != []} class="mt-6" data-testid="upcoming">
            <.timeline_entry :for={entry <- @upcoming} entry={entry} locale={@locale} />
          </ol>
        </.account_section>

        <.account_section :if={@past != []} id="past" title={~t"Past"}>
          <ol class="text-base-content/70 mt-6" data-testid="past">
            <.timeline_entry :for={entry <- Enum.take(@past, @past_visible)} entry={entry} locale={@locale} />
          </ol>
          <details :if={length(@past) > @past_visible} class="group">
            <summary class="link-underline-hover mt-4 inline-block cursor-pointer list-none text-sm group-open:hidden">
              {~t"Show #{count = length(@past) - @past_visible} more"}
            </summary>
            <ol class="text-base-content/70" data-testid="past-more">
              <.timeline_entry :for={entry <- Enum.drop(@past, @past_visible)} entry={entry} locale={@locale} />
            </ol>
          </details>
        </.account_section>

        <.account_section :if={@subscriptions == []} id="subscriptions" title={~t"Subscriptions"}>
          <div class="mt-6" data-testid="no-subscriptions">
            <p>{~t"No subscriptions yet."}</p>
            <p class="text-base-content/70 mt-2">
              {~t"Flowers every 1, 2 or 4 weeks. Pause or cancel anytime."}
            </p>
            <.button :if={@subscription_path} navigate={@subscription_path} variant="text" class="mt-4">
              {~t"See subscriptions"}
            </.button>
          </div>
        </.account_section>

        <.account_section id="details" title={~t"Your details"}>
          <.form
            :if={!@pending_email}
            for={@details_form}
            id="details-form"
            phx-submit="save_details"
            class="mt-6 flex max-w-md flex-col gap-4"
          >
            <.input field={@details_form[:name]} type="text" label={~t"Name"} autocomplete="name" />
            <.input field={@details_form[:email]} type="email" label={~t"Email"} autocomplete="email" required />
            <div class="flex items-center gap-4">
              <.button type="submit" variant="primary">{~t"Save"}</.button>
              <p role="status" class="text-base-content/70 text-sm">
                <span :if={@details_saved?}>{~t"Saved"}</span>
              </p>
            </div>
          </.form>

          <.form
            :if={@pending_email}
            for={@code_form}
            id="email-code-form"
            phx-submit="confirm_email"
            class="mt-6 flex max-w-md flex-col gap-4"
          >
            <p>{~t"We've sent a code to #{email = @pending_email}. Enter it to confirm your new email."}</p>
            <.input
              field={@code_form[:code]}
              type="text"
              label={~t"Code"}
              inputmode="numeric"
              autocomplete="one-time-code"
              required
            />
            <div class="flex items-center gap-4">
              <.button type="submit" variant="primary">{~t"Confirm"}</.button>
              <.button type="button" variant="text" phx-click="cancel_email_change">{~t"Cancel"}</.button>
            </div>
          </.form>
        </.account_section>

        <.account_section id="newsletter" title={~t"Newsletter"}>
          <.form for={%{}} id={@newsletter_form_id} phx-change="toggle_newsletter" class="mt-6">
            <label class="flex max-w-prose items-start gap-3">
              <input type="hidden" name="newsletter_opt_in" value="false" />
              <input
                type="checkbox"
                name="newsletter_opt_in"
                value="true"
                checked={@current_user.newsletter_opt_in}
                class="checkbox checkbox-sm mt-0.5"
              />
              <span>
                {~t"Send me occasional emails about what's in the shop."}
                <span class="text-base-content/70 block text-sm">
                  {~t"Only occasional emails. Unsubscribe at any time."}
                </span>
              </span>
            </label>
          </.form>

          <%!-- Height is reserved so the confirmation never nudges the page. --%>
          <p role="status" class="text-base-content/70 mt-3 h-5 text-sm">
            <span :if={@newsletter_saved?}>{~t"Saved"}</span>
          </p>
        </.account_section>
      </.container>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save_details", %{"details" => params}, socket) do
    user = socket.assigns.current_user
    name = blank_to_nil(params["name"])
    email = String.trim(params["email"] || "")

    case update_name(user, name) do
      {:ok, user} ->
        {_, socket} = maybe_start_email_change(assign(socket, current_user: user), email)
        {:noreply, socket}

      {:error, error} ->
        Logger.error(inspect(error))
        {:noreply, put_flash(socket, :error, ~t"Your details couldn't be saved.")}
    end
  end

  def handle_event("confirm_email", %{"confirm" => %{"code" => code}}, socket) do
    user = socket.assigns.current_user

    case Accounts.confirm_email_change(user, code, actor: user, load: [:first_name]) do
      {:ok, user} ->
        {:noreply, socket |> assign(current_user: user) |> reset_details(user) |> assign(details_saved?: true)}

      {:error, %Ash.Error.Invalid{errors: [%{field: :code, message: message} | _]}} ->
        {:noreply, assign(socket, code_form: to_form(%{"code" => ""}, as: :confirm, errors: [code: {message, []}]))}

      {:error, error} ->
        Logger.info("Email change failed: #{inspect(error)}")
        {:noreply, abandon_email_change(socket, email_change_error_message(error))}
    end
  end

  def handle_event("cancel_email_change", _params, socket) do
    {:noreply, reset_details(socket, socket.assigns.current_user)}
  end

  def handle_event("cancel_order", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    socket =
      with {:ok, order} <- Orders.get_order_by_id(id, actor: user),
           {:ok, _order} <- Orders.cancel_order_by_customer(order, actor: user) do
        put_flash(socket, :success, ~t"Your order is cancelled. A confirmation is on its way to your email.")
      else
        {:error, error} ->
          Logger.info("Order cancel refused: #{inspect(error)}")
          put_flash(socket, :error, order_cancel_error_message(error))
      end

    {:noreply, socket |> assign(orders: orders(user)) |> assign_timeline()}
  end

  def handle_event("toggle_newsletter", params, socket) do
    user = socket.assigns.current_user
    opt_in = params["newsletter_opt_in"] == "true"

    case Accounts.update_newsletter_preference(user, opt_in, to_string(Format.locale()), actor: user) do
      {:ok, user} ->
        token = System.unique_integer()
        Process.send_after(self(), {:clear_newsletter_saved, token}, @saved_visible_ms)

        {:noreply, assign(socket, current_user: user, newsletter_saved?: true, newsletter_saved_token: token)}

      {:error, error} ->
        Logger.error(inspect(error))

        # Nothing in the form changed server-side, so LiveView would leave the
        # box ticked. A new form id re-renders it from what was saved.
        {:noreply,
         socket
         |> assign(newsletter_form_id: "#{@newsletter_form_id}-#{System.unique_integer([:positive])}")
         |> put_flash(:error, ~t"Your newsletter preference couldn't be saved.")}
    end
  end

  # Only the most recent save clears the confirmation. Toggling twice inside the
  # visible window would otherwise let the first timer wipe the "Saved" the
  # second save has only just put up.
  @impl true
  def handle_info({:clear_newsletter_saved, token}, %{assigns: %{newsletter_saved_token: token}} = socket) do
    {:noreply, assign(socket, newsletter_saved?: false)}
  end

  def handle_info({:clear_newsletter_saved, _superseded}, socket), do: {:noreply, socket}

  def handle_info({:put_flash, kind, message}, socket), do: {:noreply, put_flash(socket, kind, message)}

  def handle_info(:subscriptions_changed, socket) do
    user = socket.assigns.current_user
    {:noreply, socket |> assign(subscriptions: subscriptions(user), orders: orders(user)) |> assign_timeline()}
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :class, :any, default: "pt-12 sm:pt-16"
  slot :inner_block, required: true

  defp account_section(assigns) do
    ~H"""
    <section class={@class} aria-labelledby={"#{@id}-heading"}>
      <h2 id={"#{@id}-heading"} class="section-title">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :href, :string, required: true

  defp receipt_link(assigns) do
    ~H"""
    <a
      href={@href}
      target="_blank"
      rel="noopener"
      aria-label={~t"Receipt (opens in a new tab)"}
      class="link-underline-static-body whitespace-nowrap text-sm"
    >
      {~t"Receipt"}<.icon name="hero-arrow-up-right-mini" class="size-3.5 align-[-0.1em] ml-0.5" />
    </a>
    """
  end

  attr :entry, :map, required: true
  attr :locale, :string, required: true

  # The same row as the public courses list: date, what it is, then its price,
  # which drops under the title below sm.
  defp timeline_entry(assigns) do
    ~H"""
    <li class="border-base-content/12 grid-cols-[5rem_1fr] grid items-baseline gap-x-4 gap-y-2 border-t py-6 sm:grid-cols-[8rem_1fr_auto] sm:gap-x-8">
      <p class="tabular-nums">
        {Format.day_month(@entry.date, @locale)}
        <span :if={@entry.date.year != ShopTime.today().year} class="block">{@entry.date.year}</span>
      </p>
      <.order_entry :if={@entry.type == :order} order={@entry.item} locale={@locale} />
      <.course_entry :if={@entry.type == :course} registration={@entry.item} upcoming?={@entry.upcoming?} locale={@locale} />
      <.subscription_entry :if={@entry.type == :subscription} subscription={@entry.item} locale={@locale} />
    </li>
    """
  end

  attr :price, :any, required: true
  attr :locale, :string, required: true
  slot :inner_block

  defp entry_price(assigns) do
    ~H"""
    <div class="col-start-2 sm:col-start-3 sm:row-start-1 sm:text-right">
      <p class="font-serif text-xl tabular-nums">{Format.storefront_price(@price, @locale)}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :order, :map, required: true
  attr :locale, :string, required: true

  defp order_entry(assigns) do
    ~H"""
    <div class="min-w-0">
      <h3 class="card-heading text-balance">{order_title(@order)}</h3>
      <p class="text-base-content/70 mt-1 text-sm">
        <span :if={@order.subscription_id} data-testid="order-subscription">{~t"Subscription order"}</span>
        <span :if={!@order.subscription_id}>{~t"Order"}</span>
        · {status_label(@order.customer_status)} · #{@order.order_reference}
      </p>
      <.unpaid_note :if={@order.unpaid?} order={@order} />
      <.order_cancel :if={@order.cancellable_by_customer?} order={@order} locale={@locale} />
    </div>
    <.entry_price price={@order.grand_total} locale={@locale}>
      <.receipt_link :if={@order.receipt_available?} href={~p"/order/#{@order.id}/receipt"} />
    </.entry_price>
    """
  end

  attr :order, :map, required: true
  attr :locale, :string, required: true

  # Asked in place, like stopping a subscription.
  defp order_cancel(assigns) do
    ~H"""
    <div class="mt-2 text-sm" data-testid="order-cancel">
      <p id={"order-#{@order.id}-cancel-actions"} class="text-base-content/70">
        {~t"You can cancel until #{date = Format.day_month(@order.cancellable_until, @locale)}"} ·
        <.button
          id={"cancel-order-#{@order.id}-open"}
          type="button"
          variant="text"
          phx-click={show_order_cancel(@order.id)}
        >
          {~t"Cancel order"}
        </.button>
      </p>
      <section id={"cancel-order-#{@order.id}"} class="hidden" aria-labelledby={"cancel-order-#{@order.id}-title"}>
        <h4 id={"cancel-order-#{@order.id}-title"} tabindex="-1" class="font-semibold outline-hidden">
          {~t"Cancel this order?"}
        </h4>
        <p class="mt-1">
          {~t"We'll refund #{amount = Format.currency(@order.amount_paid, @locale)} to your card. It can take 5–10 days to arrive."}
        </p>
        <div class="mt-3 flex flex-wrap gap-3">
          <.button type="button" variant="primary" size="sm" phx-click={hide_order_cancel(@order.id)}>
            {~t"Keep it"}
          </.button>
          <.button
            type="button"
            variant="destructive"
            size="sm"
            phx-click={JS.push("cancel_order", value: %{id: @order.id})}
          >
            {~t"Cancel order"}
          </.button>
        </div>
      </section>
    </div>
    """
  end

  defp show_order_cancel(id) do
    JS.hide(to: "#order-#{id}-cancel-actions")
    |> JS.show(to: "#cancel-order-#{id}")
    |> JS.focus(to: "#cancel-order-#{id}-title")
  end

  defp hide_order_cancel(id) do
    JS.hide(to: "#cancel-order-#{id}")
    |> JS.show(to: "#order-#{id}-cancel-actions")
    |> JS.focus(to: "#cancel-order-#{id}-open")
  end

  attr :registration, :map, required: true
  attr :upcoming?, :boolean, required: true
  attr :locale, :string, required: true

  defp course_entry(assigns) do
    ~H"""
    <div class="min-w-0">
      <h3 class="card-heading text-balance">
        <.link navigate={~q"/#{language}/courses/#{@registration.course.id}"} class="link-underline-hover">
          {@registration.course.name}
        </.link>
      </h3>
      <p class="text-base-content/70 mt-1 text-sm tabular-nums">
        {~t"Course"} · {course_state(@registration, @upcoming?, @locale)} · {@registration.course.location_name} · {~t"#{count = @registration.seats_held} place(s)"N}
      </p>
      <p :if={Decimal.positive?(@registration.balance)} class="text-base-content/70 mt-1 text-sm">
        {~t"Amount to pay: #{amount = Format.currency(@registration.balance, @locale)}."}
        <%= cond do %>
          <% @registration.payment_terms == :invoice -> %>
            {~t"Pay by invoice"}
          <% @registration.payment_link_open? -> %>
            <.link navigate={EdenflowersWeb.PaymentLink.path_for(@registration)} class="link-underline-hover text-primary">
              {~t"Pay now"}
            </.link>
          <% true -> %>
            {~t"Pay at the course"}
        <% end %>
      </p>
    </div>
    <.entry_price price={@registration.amount} locale={@locale}>
      <.receipt_link :if={@registration.receipt_available?} href={~p"/courses/bookings/#{@registration.id}/receipt"} />
    </.entry_price>
    """
  end

  defp course_state(registration, true = _upcoming?, locale),
    do: ~t"Starts #{time = Format.time(registration.course.start_time, locale)}"

  defp course_state(_registration, false = _upcoming?, _locale), do: ~t"Took place"

  attr :subscription, :map, required: true
  attr :locale, :string, required: true

  defp subscription_entry(assigns) do
    ~H"""
    <div class="min-w-0">
      <h3 class="card-heading text-balance">{SubscriptionManager.subscription_name(@subscription)}</h3>
      <p class="text-base-content/70 mt-1 text-sm">
        {~t"Subscription"} · {~t"Charged #{date = Format.day_month(@subscription.charged_on, @locale)}"}
      </p>
    </div>
    <.entry_price price={@subscription.product_variant.price} locale={@locale} />
    """
  end

  defp order_title(%{line_items: []}), do: ~t"Order"
  defp order_title(order), do: Enum.map_join(order.line_items, ", ", &line_item_label/1)

  defp line_item_label(%{quantity: 1} = item), do: Format.line_item_name(item)
  defp line_item_label(item), do: "#{item.quantity} × #{Format.line_item_name(item)}"

  # Only the empty state links to it, so it's looked up only then. The store has
  # no subscribable filter, so several products send the customer to the store.
  defp assign_subscription_path(%{assigns: %{subscriptions: []}} = socket) do
    path =
      case Catalog.list_subscribable_products!() do
        [] -> nil
        [product] -> ~q"/#{language}/product/#{product.id}"
        _several -> ~q"/#{language}/store"
      end

    assign(socket, subscription_path: path)
  end

  defp assign_subscription_path(socket), do: assign(socket, subscription_path: nil)

  defp subscriptions(user) do
    Orders.list_my_subscriptions!(actor: user)
    |> Enum.sort_by(&(&1.state == :cancelled))
  end

  defp order_cancel_error_message(%Ash.Error.Invalid{errors: [%{message: message} | _]}) when is_binary(message),
    do: message

  defp order_cancel_error_message(_error), do: ~t"This order couldn't be cancelled. Please contact us."

  defp update_name(user, name) when name == user.name, do: {:ok, user}

  defp update_name(user, name), do: Accounts.update_name(user, name, actor: user, load: [:first_name])

  defp maybe_start_email_change(socket, email) do
    user = socket.assigns.current_user

    if String.downcase(email) == String.downcase(to_string(user.email)) do
      {:ok, socket |> reset_details(user) |> assign(details_saved?: true)}
    else
      case Accounts.request_email_change(user, email, actor: user) do
        {:ok, user} ->
          {:ok, assign(socket, pending_email: user.pending_email, code_form: to_form(%{"code" => ""}, as: :confirm))}

        {:error, %Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{} | _]}} ->
          {:error,
           assign(socket,
             details_form: details_form(user, email, email: ~t"Too many attempts. Please try again later.")
           )}

        {:error, error} ->
          Logger.info("Email change request failed: #{inspect(error)}")
          {:error, assign(socket, details_form: details_form(user, email, email: ~t"Enter a valid email address."))}
      end
    end
  end

  defp email_change_error_message(%Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{} | _]}),
    do: ~t"Too many wrong codes. Please try again."

  defp email_change_error_message(%Ash.Error.Invalid{errors: [%{field: :pending_email, message: message} | _]}),
    do: message

  defp email_change_error_message(_error), do: ~t"That email can't be used. It may already belong to another account."

  defp abandon_email_change(socket, message) do
    user = socket.assigns.current_user
    email = socket.assigns.pending_email

    socket
    |> reset_details(user)
    |> assign(details_form: details_form(user, email, email: message))
  end

  defp reset_details(socket, user) do
    assign(socket, details_form: details_form(user), pending_email: nil, details_saved?: false)
  end

  defp details_form(user, email \\ nil, errors \\ []) do
    to_form(
      %{"name" => user.name || "", "email" => email || to_string(user.email)},
      as: :details,
      errors: Enum.map(errors, fn {field, message} -> {field, {message, []}} end),
      action: if(errors != [], do: :validate)
    )
  end

  defp blank_to_nil(value) do
    case String.trim(value || "") do
      "" -> nil
      trimmed -> trimmed
    end
  end

  attr :order, :map, required: true

  defp unpaid_note(assigns) do
    assigns = assign(assigns, :note, payment_note(assigns.order))

    ~H"""
    <span :if={@note} class="text-base-content/70 block text-sm" data-testid="order-unpaid">
      <%= if @note == :pay_now do %>
        <span class="text-error">{~t"Unpaid"}</span>
        ·
        <.link navigate={~p"/pay/orders/#{@order.payment_link_token}"} class="link-underline-hover text-primary">
          {~t"Pay now"}
        </.link>
      <% else %>
        {@note}
      <% end %>
    </span>
    """
  end

  # Only how Jennie said they'd pay: once handed over, "in person" no longer holds.
  defp payment_note(%{payment_link_open?: true}), do: :pay_now
  defp payment_note(%{payment_terms: :invoice}), do: ~t"Pay by invoice"

  defp payment_note(%{payment_terms: :on_fulfillment, fulfillment_status: :pending, fulfillment_method: :delivery}),
    do: ~t"Pay on delivery"

  defp payment_note(%{payment_terms: :on_fulfillment, fulfillment_status: :pending}), do: ~t"Pay at collection"
  defp payment_note(_order), do: nil

  # The customer's words for an order's `customer_status`. The date sits beside it.
  defp status_label(:refunded), do: ~t"Refunded"
  defp status_label(:cancelled), do: ~t"Cancelled"
  defp status_label(:confirmed), do: ~t"Confirmed"
  defp status_label(:collected), do: ~t"Collected"
  defp status_label(:delivered), do: ~t"Delivered"
  defp status_label(:ready_today), do: ~t"Ready to collect today"
  defp status_label(:arriving_today), do: ~t"Arriving today"
  defp status_label(:for_pickup), do: ~t"For pickup"
  defp status_label(:arriving), do: ~t"Arriving"
  defp status_label(:pickup_scheduled), do: ~t"Scheduled pickup"
  defp status_label(:delivery_scheduled), do: ~t"Scheduled delivery"

  defp orders(user), do: Orders.list_my_orders!(actor: user, load: [:line_items])

  defp assign_timeline(socket) do
    %{orders: orders, registrations: registrations, subscriptions: subscriptions} = socket.assigns

    order_entries =
      Enum.map(orders, &%{type: :order, item: &1, date: order_date(&1), upcoming?: &1.upcoming?})

    course_entries =
      Enum.map(registrations, &%{type: :course, item: &1, date: &1.course.date, upcoming?: &1.upcoming?})

    # A delivery already booked is an order above; this is the one after it.
    subscription_entries =
      for subscription <- subscriptions, subscription.next_delivery_date do
        %{type: :subscription, item: subscription, date: subscription.next_delivery_date, upcoming?: true}
      end

    {upcoming, past} = Enum.split_with(order_entries ++ course_entries ++ subscription_entries, & &1.upcoming?)

    assign(socket,
      upcoming: Enum.sort_by(upcoming, & &1.date, Date),
      past: Enum.sort_by(past, & &1.date, {:desc, Date})
    )
  end

  defp order_date(order), do: order.fulfillment_date || ordered_on(order)

  defp registrations(user) do
    Courses.list_my_registrations!(
      actor: user,
      load: [:course, :seats_held, :upcoming?, :balance, :receipt_available?, :payment_link_open?]
    )
    |> Translations.translate_assoc(:course)
  end

  defp ordered_on(order), do: helsinki_date(order.ordered_at || order.inserted_at)

  defp helsinki_date(datetime), do: datetime |> DateTime.shift_zone!(ShopTime.timezone()) |> DateTime.to_date()
end

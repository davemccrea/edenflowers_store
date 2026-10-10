defmodule EdenflowersWeb.Account.AccountLive do
  use EdenflowersWeb, :live_view

  require Ash.Query
  require Logger

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Workers.SendEmailChangeCode
  alias Edenflowers.Catalog
  alias Edenflowers.Courses
  alias Edenflowers.Expressions.HelsinkiToday
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment.Weekday
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.RateLimiter
  alias Edenflowers.Translations
  alias EdenflowersWeb.Admin.Components, as: AdminComponents
  alias EdenflowersWeb.Checkout.Fields

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_required}

  @timezone "Europe/Helsinki"
  @saved_visible_ms 2500
  @newsletter_form_id "newsletter-preference"
  @email_code_ttl_ms :timer.minutes(10)
  @email_code_attempts 5
  @email_codes_per_window 5
  @email_code_window_ms :timer.minutes(15)
  @past_visible 5

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
     |> assign(edited_subscriptions: MapSet.new())
     |> assign(subscription_notice: nil)
     |> assign_subscription_product()
     |> assign(registrations: registrations(user))
     |> assign(past_visible: @past_visible)
     |> assign_timeline()
     |> assign(newsletter_form_id: @newsletter_form_id)
     |> assign(newsletter_saved?: false)
     |> assign(newsletter_saved_token: nil)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container class="max-w-3xl">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-baseline sm:justify-between">
          <h1 class="page-title">
            {if @current_user.first_name, do: ~t"Hi, #{@current_user.first_name}", else: ~t"Account"}
          </h1>
          <.button href={~p"/sign-out"} method="delete" variant="secondary" size="sm" class="w-fit">
            {~t"Sign out"}
          </.button>
        </div>

        <.account_section :if={@subscriptions != []} id="subscriptions" title={~t"Subscriptions"}>
          <ol class="mt-6" data-testid="subscriptions">
            <li
              :for={subscription <- @subscriptions}
              id={"subscription-#{subscription.id}"}
              class="border-base-content/12 border-t py-6"
            >
              <div class="grid-cols-[1fr_auto] grid items-baseline gap-x-4">
                <h3 id={"subscription-#{subscription.id}-name"} class="card-heading text-balance">
                  {subscription_name(subscription)}
                </h3>
                <p class="font-serif text-xl tabular-nums">
                  {Format.storefront_price(subscription.product_variant.price, @locale)}
                </p>
                <p class="text-base-content/70 mt-1 text-sm">{plan_label(subscription)}</p>
                <p class="text-base-content/70 text-right text-sm">{~t"per delivery"}</p>
              </div>

              <div class="mt-5 flex items-end justify-between gap-4">
                <div data-testid="subscription-status">
                  <p class="eyebrow text-base-content/70 mb-2">
                    {if subscription.state == :active, do: ~t"Next delivery", else: ~t"Status"}
                  </p>
                  <.next_delivery subscription={subscription} orders={@orders} locale={@locale} />
                </div>
                <.manage_button subscription={subscription} />
              </div>
            </li>
          </ol>

          <.manage_drawer
            :for={subscription <- @subscriptions}
            subscription={subscription}
            orders={@orders}
            locale={@locale}
            edited?={subscription.id in @edited_subscriptions}
            notice={notice_for(@subscription_notice, subscription)}
          />
        </.account_section>

        <.account_section id="upcoming" title={~t"Coming up"}>
          <div :if={@upcoming == []} class="mt-6">
            <p class="text-base-content/80">{~t"Nothing on its way."}</p>
            <div class="mt-4 flex flex-wrap gap-x-6 gap-y-2">
              <.button navigate={~p"/store"} variant="text">{~t"Visit the shop"}</.button>
              <.button navigate={~p"/courses"} variant="text">{~t"See what's coming up"}</.button>
            </div>
          </div>

          <ol :if={@upcoming != []} class="mt-6" data-testid="upcoming">
            <.timeline_entry :for={entry <- @upcoming} entry={entry} locale={@locale} />
          </ol>
        </.account_section>

        <.account_section :if={@past != []} id="past" title={~t"Past"}>
          <ol class="mt-6" data-testid="past">
            <.timeline_entry :for={entry <- Enum.take(@past, @past_visible)} entry={entry} locale={@locale} />
          </ol>
          <details :if={length(@past) > @past_visible} class="group">
            <summary class="link-underline-hover mt-4 inline-block cursor-pointer list-none text-sm group-open:hidden">
              {~t"Show #{count = length(@past) - @past_visible} more"}
            </summary>
            <ol data-testid="past-more">
              <.timeline_entry :for={entry <- Enum.drop(@past, @past_visible)} entry={entry} locale={@locale} />
            </ol>
          </details>
        </.account_section>

        <.account_section :if={@subscriptions == []} id="subscriptions" title={~t"Subscriptions"}>
          <div class="mt-6" data-testid="no-subscriptions">
            <p class="text-base-content/80">
              {~t"A florist's-choice bouquet every 1, 2 or 4 weeks. Pause or cancel from your account."}
            </p>
            <.button
              :if={@subscription_product}
              navigate={~p"/product/#{@subscription_product.id}"}
              variant="text"
              class="mt-4"
            >
              {~t"See the subscription"}
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
              <.button type="submit" variant="primary" phx-disable-with={~t"Saving…"}>{~t"Save"}</.button>
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
            <p>{~t"We've sent a code to #{@pending_email.email}. Enter it to confirm your new email."}</p>
            <.input
              field={@code_form[:code]}
              type="text"
              label={~t"Code"}
              inputmode="numeric"
              autocomplete="one-time-code"
              required
            />
            <div class="flex items-center gap-4">
              <.button type="submit" variant="primary" phx-disable-with={~t"Confirming…"}>{~t"Confirm"}</.button>
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

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp account_section(assigns) do
    ~H"""
    <section class="pt-12 sm:pt-16" aria-labelledby={"#{@id}-heading"}>
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
      class="link-underline-static-body text-base-content/70 whitespace-nowrap text-sm"
    >
      {~t"Receipt"}
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
      <p class="text-base-content/70 tabular-nums">
        {Format.day_month(@entry.date, @locale)}
        <span :if={@entry.date.year != HelsinkiToday.today().year} class="block">{@entry.date.year}</span>
      </p>
      <.order_entry :if={@entry.type == :order} order={@entry.item} locale={@locale} />
      <.course_entry :if={@entry.type == :course} registration={@entry.item} locale={@locale} />
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
        {status_label(@order)} · #{@order.order_reference}
        <span :if={@order.subscription_id} data-testid="order-subscription">· {~t"Subscription"}</span>
      </p>
      <.unpaid_note :if={@order.unpaid?} order={@order} />
    </div>
    <.entry_price price={@order.grand_total} locale={@locale}>
      <.receipt_link :if={@order.payment_status == :paid} href={~p"/order/#{@order.id}/receipt"} />
    </.entry_price>
    """
  end

  attr :registration, :map, required: true
  attr :locale, :string, required: true

  defp course_entry(assigns) do
    ~H"""
    <div class="min-w-0">
      <h3 class="card-heading text-balance">
        <.link navigate={~p"/courses/#{@registration.course.id}"} class="link-underline-hover">
          {@registration.course.name}
        </.link>
      </h3>
      <p class="text-base-content/70 mt-1 text-sm tabular-nums">
        {Format.time(@registration.course.start_time, @locale)} · {@registration.course.location_name} · {~t"#{count = @registration.seats_held} place(s)"N}
      </p>
    </div>
    <.entry_price price={@registration.amount} locale={@locale}>
      <.receipt_link href={~p"/courses/bookings/#{@registration.id}/receipt"} />
    </.entry_price>
    """
  end

  attr :subscription, :map, required: true
  attr :locale, :string, required: true

  defp subscription_entry(assigns) do
    ~H"""
    <div class="min-w-0">
      <h3 class="card-heading text-balance">{subscription_name(@subscription)}</h3>
      <p class="text-base-content/70 mt-1 text-sm">
        {~t"Subscription"} · {~t"Charged #{date = Format.day_month(Subscription.charged_on(@subscription.next_fulfillment_date), @locale)}"}
      </p>
    </div>
    <.entry_price price={@subscription.product_variant.price} locale={@locale} />
    """
  end

  defp order_title(%{line_items: []}), do: ~t"Order"
  defp order_title(order), do: Enum.map_join(order.line_items, ", ", &line_item_label/1)

  defp line_item_label(%{quantity: 1} = item), do: item.product_name
  defp line_item_label(item), do: "#{item.quantity} × #{item.product_name}"

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
    pending = socket.assigns.pending_email
    user = socket.assigns.current_user

    cond do
      pending == nil ->
        {:noreply, socket}

      System.monotonic_time(:millisecond) > pending.expires_at ->
        {:noreply, abandon_email_change(socket, ~t"That code has expired. Please try again.")}

      not Plug.Crypto.secure_compare(String.trim(code), pending.code) ->
        attempts = pending.attempts + 1

        if attempts >= @email_code_attempts do
          {:noreply, abandon_email_change(socket, ~t"Too many wrong codes. Please try again.")}
        else
          {:noreply,
           socket
           |> assign(pending_email: %{pending | attempts: attempts})
           |> assign(
             code_form: to_form(%{"code" => ""}, as: :confirm, errors: [code: {~t"That code isn't right.", []}])
           )}
        end

      true ->
        case Accounts.change_email(user, pending.email, actor: user, load: [:first_name]) do
          {:ok, user} ->
            {:noreply, socket |> assign(current_user: user) |> reset_details(user) |> assign(details_saved?: true)}

          {:error, error} ->
            Logger.info("Email change failed: #{inspect(error)}")

            {:noreply,
             abandon_email_change(socket, ~t"That email can't be used. It may already belong to another account.")}
        end
    end
  end

  def handle_event("cancel_email_change", _params, socket) do
    {:noreply, reset_details(socket, socket.assigns.current_user)}
  end

  def handle_event("pause_subscription", %{"id" => id}, socket) do
    {:noreply, change_subscription(socket, id, &Orders.pause_subscription/2, fn _ -> ~t"Subscription paused" end)}
  end

  def handle_event("resume_subscription", %{"id" => id}, socket) do
    {:noreply, change_subscription(socket, id, &Orders.resume_subscription/2, fn _ -> ~t"Subscription resumed" end)}
  end

  def handle_event("cancel_subscription", %{"id" => id}, socket) do
    {:noreply, change_subscription(socket, id, &Orders.cancel_subscription/2, fn _ -> ~t"Subscription cancelled" end)}
  end

  def handle_event("edit_subscription", %{"subscription_id" => id} = params, socket) do
    subscription = Enum.find(socket.assigns.subscriptions, &(&1.id == id))

    edited? =
      subscription != nil and
        (params["product_variant_id"] != subscription.product_variant_id or
           params["interval_weeks"] != to_string(subscription.interval_weeks) or
           params["delivery_day"] != to_string(delivery_day(subscription)))

    edited =
      if edited?,
        do: MapSet.put(socket.assigns.edited_subscriptions, id),
        else: MapSet.delete(socket.assigns.edited_subscriptions, id)

    {:noreply, assign(socket, edited_subscriptions: edited)}
  end

  def handle_event("change_subscription", %{"subscription_id" => id} = params, socket) do
    changes = Map.take(params, ["product_variant_id", "interval_weeks", "delivery_day"])
    change = &Orders.change_subscription(&1, changes, Keyword.put(&2, :load, :product_variant))

    socket =
      socket
      |> change_subscription(id, change, &change_confirmation(&1, socket.assigns.locale))
      |> assign(edited_subscriptions: MapSet.delete(socket.assigns.edited_subscriptions, id))

    {:noreply, socket}
  end

  def handle_event("toggle_newsletter", params, socket) do
    user = socket.assigns.current_user
    opt_in = params["newsletter_opt_in"] == "true"

    case Accounts.update_newsletter_preference(user, opt_in, actor: user) do
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
  def handle_info({:clear_newsletter_saved, token}, %{assigns: %{newsletter_saved_token: token}} = socket) do
    {:noreply, assign(socket, newsletter_saved?: false)}
  end

  def handle_info({:clear_newsletter_saved, _superseded}, socket), do: {:noreply, socket}

  # The outcome shows inside the subscription's drawer, which sits above the
  # page's flash while it's open.
  defp change_subscription(socket, id, action, success_message) do
    user = socket.assigns.current_user

    socket =
      case Orders.get_subscription(id, actor: user) do
        {:ok, subscription} ->
          case action.(subscription, actor: user) do
            {:ok, subscription} ->
              assign(socket, subscription_notice: {id, :info, success_message.(subscription)})

            {:error, error} ->
              Logger.info("Subscription change refused: #{inspect(error)}")
              assign(socket, subscription_notice: {id, :error, subscription_error_message(error)})
          end

        {:error, error} ->
          Logger.info("Subscription change refused: #{inspect(error)}")
          put_flash(socket, :error, subscription_error_message(error))
      end

    socket
    |> assign(subscriptions: subscriptions(user), orders: orders(user))
    |> assign_timeline()
  end

  # Only the empty state links to it, so it's looked up only then.
  defp assign_subscription_product(%{assigns: %{subscriptions: []}} = socket) do
    query = Ash.Query.filter(Edenflowers.Catalog.Product, subscribable == true)
    assign(socket, subscription_product: List.first(Catalog.list_store_products!(query: query)))
  end

  defp assign_subscription_product(socket), do: assign(socket, subscription_product: nil)

  defp subscriptions(user) do
    Orders.list_my_subscriptions!(actor: user)
    |> Enum.sort_by(&(&1.state == :cancelled))
  end

  # The cutoff's own message says why; anything else means the page was stale.
  defp subscription_error_message(%Ash.Error.Invalid{errors: errors}) do
    Enum.find_value(errors, ~t"Your subscription couldn't be changed.", fn
      %Ash.Error.Changes.InvalidAttribute{field: :next_fulfillment_date, message: message} -> message
      _ -> nil
    end)
  end

  defp subscription_error_message(_error), do: ~t"Your subscription couldn't be changed."

  defp size_options(subscription, locale) do
    for variant <- subscription.product_variant.product.product_variants,
        not variant.draft or variant.id == subscription.product_variant_id do
      {"#{AdminComponents.variant_size_label(variant.size)} · #{Format.storefront_price(variant.price, locale)}",
       variant.id}
    end
  end

  defp delivery_day(subscription), do: Weekday.from_date(subscription.next_fulfillment_date)

  defp delivery_day_options(subscription, locale) do
    for day <- Weekday.all(), day in subscription.fulfillment_option.available_days do
      {String.capitalize(Format.weekday_name(day, locale)), day}
    end
  end

  # The occurrence job reads the subscription when it books each delivery, so a
  # change applies from the first one it hasn't booked.
  defp change_confirmation(subscription, locale) do
    %{product_variant: variant, interval_weeks: weeks} = subscription
    from = Format.weekday_date(subscription.next_fulfillment_date, locale)
    size = AdminComponents.variant_size_label(variant.size)
    price = Format.storefront_price(variant.price, locale)

    ~t"From #{date = from}: #{size = size}, #{interval = String.downcase(Fields.interval_label(weeks))}, #{price = price} per delivery."
  end

  attr :subscription, :map, required: true
  attr :booked, :map, default: nil
  attr :locale, :string, required: true

  # Asked in place rather than in a dialog, since the drawer is already a layer
  # of its own.
  defp cancel_confirmation(assigns) do
    assigns = assign(assigns, id: assigns.subscription.id, final_delivery?: final_delivery?(assigns.booked))

    ~H"""
    <section
      id={"cancel-subscription-#{@id}"}
      class="mt-4 hidden"
      aria-labelledby={"cancel-subscription-#{@id}-title"}
    >
      <h3 id={"cancel-subscription-#{@id}-title"} tabindex="-1" class="card-heading outline-hidden">
        {~t"Stop your subscription?"}
      </h3>
      <p :if={@final_delivery?} class="mt-2" data-testid="final-delivery-warning">
        {~t"Your delivery on #{date = Format.weekday_date(@booked.fulfillment_date, @locale)} is already being prepared and will be your final delivery. There will be no deliveries or charges after that."}
      </p>
      <p :if={not @final_delivery?} class="mt-2">{~t"There will be no more deliveries or charges."}</p>
      <p :if={@subscription.state == :active} class="mt-2">
        {~t"Want a break instead?"}
        <.button
          type="button"
          variant="text"
          phx-click={JS.push("pause_subscription", value: %{id: @id}) |> hide_cancel_confirmation(@id)}
        >
          {~t"Pause it"}
        </.button>
      </p>
      <div class="mt-5 flex flex-wrap gap-3">
        <.button type="button" variant="primary" phx-click={hide_cancel_confirmation(@id)}>
          {~t"Keep it"}
        </.button>
        <.button type="button" variant="destructive" phx-click={JS.push("cancel_subscription", value: %{id: @id})}>
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
          navigate={~p"/pay/#{@unpaid.payment_link_token}"}
          variant={if @held?, do: "secondary", else: "primary"}
          data-testid="subscription-pay-now"
        >
          {~t"Pay #{amount = Format.currency(@unpaid.grand_total, @locale)} now"}
        </.button>
      </div>
    </div>
    """
  end

  defp subscription_name(subscription), do: Translations.translate(subscription.product_variant.product).name

  defp plan_label(%{product_variant: variant, interval_weeks: weeks}) do
    "#{AdminComponents.variant_size_label(variant.size)} · #{Fields.interval_label(weeks)}"
  end

  defp notice_for({id, kind, message}, %{id: id}), do: {kind, message}
  defp notice_for(_notice, _subscription), do: nil

  # The occurrence job books each delivery ahead of its date, after which
  # `next_fulfillment_date` has already moved on to the one after.
  defp booked_delivery(orders, subscription) do
    orders
    |> Enum.filter(fn order ->
      order.subscription_id == subscription.id and order.fulfillment_status != :cancelled and
        not Date.before?(order.fulfillment_date, HelsinkiToday.today())
    end)
    |> Enum.min_by(& &1.fulfillment_date, Date, fn -> nil end)
  end

  defp final_delivery?(nil), do: false

  defp final_delivery?(order) do
    not Subscription.changes_open_for?(order.subscription_date || order.fulfillment_date)
  end

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
  attr :orders, :list, required: true
  attr :locale, :string, required: true

  # The list's short form: the date, then one line on what's happening.
  defp next_delivery(%{subscription: %{state: :payment_failed}} = assigns) do
    assigns = assign(assigns, unpaid: Subscription.unpaid_occurrence(assigns.orders, assigns.subscription))

    ~H"""
    <span class="font-medium">{~t"Payment failed"}</span>
    <span class="block text-sm">
      <.link
        :if={@unpaid}
        navigate={~p"/pay/#{@unpaid.payment_link_token}"}
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
    assigns = assign(assigns, booked: booked_delivery(assigns.orders, assigns.subscription))

    ~H"""
    {~t"Paused"}
    <span :if={@booked} class="text-base-content/70 block text-sm">
      {~t"After #{date = Format.day_month(@booked.fulfillment_date, @locale)}"}
    </span>
    <span :if={!@booked} class="text-base-content/70 block text-sm">{~t"No deliveries or charges"}</span>
    """
  end

  defp next_delivery(%{subscription: %{state: :cancelled}} = assigns) do
    assigns = assign(assigns, booked: booked_delivery(assigns.orders, assigns.subscription))

    ~H"""
    <%= if @booked do %>
      <span class="font-medium tabular-nums">{Format.weekday_day_month(@booked.fulfillment_date, @locale)}</span>
      <span class="text-base-content/70 block text-sm">{~t"One final delivery remains"}</span>
    <% else %>
      {~t"Cancelled"}
      <span class="text-base-content/70 block text-sm tabular-nums">
        {Format.day_month(helsinki_date(@subscription.updated_at), @locale)}
      </span>
    <% end %>
    """
  end

  defp next_delivery(assigns) do
    %{subscription: subscription, orders: orders} = assigns

    assigns =
      assign(assigns,
        booked: booked_delivery(orders, subscription),
        unpaid: Subscription.unpaid_occurrence(orders, subscription),
        next: subscription.next_fulfillment_date
      )

    ~H"""
    <span class="tabular-nums">
      {Format.weekday_day_month(if(@booked, do: @booked.fulfillment_date, else: @next), @locale)}
    </span>
    <span class="text-base-content/70 block text-sm">
      <%= cond do %>
        <% @unpaid -> %>
          {~t"Unpaid"} ·
          <.link navigate={~p"/pay/#{@unpaid.payment_link_token}"} class="link-underline-hover text-primary">
            {~t"Pay now"}
          </.link>
        <% @booked -> %>
          {~t"Being prepared"}
        <% true -> %>
          {~t"Charged #{date = Format.day_month(Subscription.charged_on(@next), @locale)}"}
      <% end %>
    </span>
    """
  end

  attr :subscription, :map, required: true
  attr :orders, :list, required: true
  attr :locale, :string, required: true
  attr :edited?, :boolean, required: true
  attr :notice, :any, default: nil

  defp manage_drawer(assigns) do
    %{subscription: subscription, orders: orders} = assigns

    assigns =
      assign(assigns,
        id: subscription.id,
        unpaid: Subscription.unpaid_occurrence(orders, subscription),
        booked: booked_delivery(orders, subscription),
        open?: subscription.state != :cancelled and not subscription.changes_closed?
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
        <p
          :if={@notice}
          role="status"
          class={["bg-cream text-cream-content px-4 py-3 text-sm", elem(@notice, 0) == :error && "text-error"]}
          data-testid="subscription-notice"
        >
          {elem(@notice, 1)}
        </p>

        <.subscription_payment subscription={@subscription} unpaid={@unpaid} locale={@locale} />

        <dl class="border-base-content/12 border-t">
          <.detail_row label={if @subscription.state == :active, do: ~t"Next delivery", else: ~t"Status"}>
            <div data-testid="subscription-drawer-status">
              <.drawer_status subscription={@subscription} booked={@booked} locale={@locale} />
            </div>

            <p :if={@subscription.changes_closed?} class="text-base-content/70 mt-2 text-sm" data-testid="changes-closed">
              {~t"Your next delivery is already being prepared. You can make changes again from #{date = Format.weekday_date(Subscription.changes_reopen_on(@subscription), @locale)}."}
              <.link navigate={~p"/contact"} class="link-underline-hover text-primary">
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
                :if={@open? and @subscription.state in [:active, :paused]}
                id={"subscription-#{@id}-pause"}
                type="button"
                variant={if @subscription.state == :paused, do: "primary", else: "secondary"}
                phx-click={if @subscription.state == :active, do: "pause_subscription", else: "resume_subscription"}
                phx-value-id={@id}
              >
                {if @subscription.state == :active, do: ~t"Pause", else: ~t"Resume"}
              </.button>
              <.button
                id={"cancel-subscription-#{@id}-open"}
                type="button"
                variant="text"
                class="text-base-content/70 min-h-11"
                aria-controls={"cancel-subscription-#{@id}"}
                phx-click={show_cancel_confirmation(@id)}
              >
                {~t"Cancel subscription"}
              </.button>
            </div>

            <.cancel_confirmation
              :if={@subscription.state != :cancelled}
              subscription={@subscription}
              booked={@booked}
              locale={@locale}
            />

            <.button
              :if={@subscription.state == :cancelled}
              navigate={~p"/product/#{@subscription.product_variant.product_id}"}
              variant="secondary"
              class="mt-3"
            >
              {~t"Start a new subscription"}
            </.button>
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
                :if={@open? and @subscription.state in [:active, :paused]}
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
              :if={@open? and @subscription.state in [:active, :paused]}
              id={"change-subscription-#{@id}"}
              phx-change="edit_subscription"
              phx-submit="change_subscription"
              class="mt-4 hidden flex-col gap-3"
            >
              <input type="hidden" name="subscription_id" value={@id} />
              <.input
                type="select"
                id={"subscription-#{@id}-size"}
                name="product_variant_id"
                label={~t"Size"}
                options={size_options(@subscription, @locale)}
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
                options={delivery_day_options(@subscription, @locale)}
                value={delivery_day(@subscription)}
              />
              <.button
                type="submit"
                variant="primary"
                class="self-start"
                disabled={not @edited?}
                phx-disable-with={~t"Saving…"}
              >
                {~t"Save changes"}
              </.button>
            </form>
          </.detail_row>

          <.detail_row :if={@subscription.state != :cancelled and @subscription.delivery_address} label={~t"Delivers to"}>
            <p class="font-serif text-lg" data-testid="subscription-recipient">
              <span :if={@subscription.recipient_name} class="block">{@subscription.recipient_name}</span>
              {@subscription.delivery_address}
            </p>
            <p class="text-base-content/70 mt-1 text-sm">
              {~t"Moving?"}
              <.link navigate={~p"/contact"} class="link-underline-hover text-base-content">
                {~t"Contact us to change the address."}
              </.link>
            </p>
          </.detail_row>

          <.detail_row :if={@subscription.state not in [:cancelled, :payment_failed]} label={~t"Card"}>
            <div class="flex items-baseline justify-between gap-4">
              <p data-testid="subscription-card">
                <Fields.saved_card :if={@subscription.card_brand} card={@subscription} />
                <span :if={!@subscription.card_brand}>{~t"Saved card"}</span>
              </p>
              <.link
                navigate={~p"/account/subscriptions/#{@id}/card"}
                class="link-underline-static-body min-h-11 inline-flex shrink-0 items-center"
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
      <p class="text-base-content/70 text-sm">{~t"Already booked and being prepared."}</p>
      <p class="text-base-content/70 text-sm">
        {~t"The one after: #{date = Format.weekday_date(@next, @locale)}, charged on #{charge_date = Format.weekday_date(Subscription.charged_on(@next), @locale)}."}
      </p>
    <% else %>
      <p class="font-serif text-lg">{Format.weekday_date(@next, @locale)}</p>
      <p class="text-base-content/70 text-sm">
        {~t"Charged to your card on #{date = Format.weekday_date(Subscription.charged_on(@next), @locale)}."}
      </p>
    <% end %>
    """
  end

  defp drawer_status(%{subscription: %{state: :paused}} = assigns) do
    ~H"""
    <p class="font-serif text-lg">{~t"Paused"}</p>
    <p :if={@booked} class="text-base-content/70 text-sm">
      {~t"Your delivery on #{date = Format.weekday_date(@booked.fulfillment_date, @locale)} is already being prepared and still comes."}
    </p>
    <p class="text-base-content/70 text-sm">
      {~t"No deliveries or charges. Resume now and your next delivery is #{date = Format.weekday_date(Subscription.resume_date(@subscription), @locale)}."}
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
    <%= if @booked do %>
      <p class="font-serif text-lg">{~t"One final delivery remains"}</p>
      <p class="text-base-content/70 text-sm">
        {~t"Your delivery on #{date = Format.weekday_date(@booked.fulfillment_date, @locale)} was already being prepared when you cancelled. There will be no deliveries or charges after that."}
      </p>
    <% else %>
      <p class="font-serif text-lg">
        {~t"Cancelled on #{date = Format.weekday_date(helsinki_date(@subscription.updated_at), @locale)}."}
      </p>
    <% end %>
    """
  end

  defp update_name(user, name) when name == user.name, do: {:ok, user}

  defp update_name(user, name), do: Accounts.update_name(user, name, actor: user, load: [:first_name])

  defp maybe_start_email_change(socket, email) do
    user = socket.assigns.current_user

    cond do
      String.downcase(email) == String.downcase(to_string(user.email)) ->
        {:ok, socket |> reset_details(user) |> assign(details_saved?: true)}

      not String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/) ->
        {:error, assign(socket, details_form: details_form(user, email, email: ~t"Enter a valid email address."))}

      # Each code goes to an address the customer only claims to own, so cap how
      # many they can fire off.
      match?({:deny, _}, RateLimiter.hit("email_change:#{user.id}", @email_code_window_ms, @email_codes_per_window)) ->
        {:error,
         assign(socket, details_form: details_form(user, email, email: ~t"Too many attempts. Please try again later."))}

      true ->
        code = generate_code()

        {:ok, _job} =
          SendEmailChangeCode.enqueue(%{
            "email" => email,
            "code" => code,
            "locale" => Gettext.get_locale(EdenflowersWeb.Gettext)
          })

        pending = %{
          email: email,
          code: code,
          attempts: 0,
          expires_at: System.monotonic_time(:millisecond) + @email_code_ttl_ms
        }

        {:ok, assign(socket, pending_email: pending, code_form: to_form(%{"code" => ""}, as: :confirm))}
    end
  end

  defp generate_code do
    :crypto.strong_rand_bytes(4)
    |> :binary.decode_unsigned()
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  defp abandon_email_change(socket, message) do
    user = socket.assigns.current_user
    email = socket.assigns.pending_email.email

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
    ~H"""
    <span class="text-base-content/70 block text-sm" data-testid="order-unpaid">
      <%= cond do %>
        <% @order.payment_link_open? -> %>
          {~t"Unpaid"} ·
          <.link navigate={~p"/pay/#{@order.payment_link_token}"} class="link-underline-hover text-primary">
            {~t"Pay now"}
          </.link>
        <% @order.fulfillment_method == :delivery -> %>
          {~t"Pay on delivery"}
        <% true -> %>
          {~t"Pay at collection"}
      <% end %>
    </span>
    """
  end

  @doc """
  Plain-language order status for the customer. The date sits beside it.

  Never claims an outcome the data doesn't support: an order whose fulfillment
  date has passed but which Jennie hasn't marked fulfilled reads as scheduled,
  not "Delivered".
  """
  def status_label(order)

  def status_label(%{payment_status: :refunded}), do: ~t"Refunded"

  def status_label(%{fulfillment_status: :cancelled}), do: ~t"Cancelled"

  def status_label(%{fulfillment_date: nil}), do: ~t"Confirmed"

  def status_label(%{fulfillment_status: :fulfilled, fulfillment_method: :pickup}), do: ~t"Collected"

  def status_label(%{fulfillment_status: :fulfilled}), do: ~t"Delivered"

  def status_label(order) do
    case {Date.compare(order.fulfillment_date, HelsinkiToday.today()), order.fulfillment_method} do
      {:eq, :pickup} -> ~t"Ready to collect today"
      {:eq, _} -> ~t"Arriving today"
      {:gt, :pickup} -> ~t"For pickup"
      {:gt, _} -> ~t"Arriving"
      {:lt, :pickup} -> ~t"Scheduled pickup"
      {:lt, _} -> ~t"Scheduled delivery"
    end
  end

  defp orders(user), do: Orders.list_my_orders!(actor: user, load: [:line_items])

  defp assign_timeline(socket) do
    %{orders: orders, registrations: registrations, subscriptions: subscriptions} = socket.assigns
    today = HelsinkiToday.today()

    order_entries =
      Enum.map(orders, &%{type: :order, item: &1, date: order_date(&1), upcoming?: upcoming_order?(&1, today)})

    course_entries =
      Enum.map(registrations, fn registration ->
        date = registration.course.date
        %{type: :course, item: registration, date: date, upcoming?: not Date.before?(date, today)}
      end)

    # A delivery already booked is an order above; this is the one after it.
    subscription_entries =
      for subscription <- subscriptions, subscription.state == :active do
        %{type: :subscription, item: subscription, date: subscription.next_fulfillment_date, upcoming?: true}
      end

    {upcoming, past} = Enum.split_with(order_entries ++ course_entries ++ subscription_entries, & &1.upcoming?)

    assign(socket,
      upcoming: Enum.sort_by(upcoming, & &1.date, Date),
      past: Enum.sort_by(past, & &1.date, {:desc, Date})
    )
  end

  defp order_date(order), do: order.fulfillment_date || ordered_on(order)

  defp upcoming_order?(%{payment_status: :refunded}, _today), do: false
  defp upcoming_order?(%{fulfillment_status: status}, _today) when status in [:cancelled, :fulfilled], do: false
  defp upcoming_order?(%{fulfillment_date: nil}, _today), do: true
  defp upcoming_order?(order, today), do: not Date.before?(order.fulfillment_date, today)

  defp registrations(user) do
    Courses.list_my_registrations!(actor: user, load: [:course, :seats_held])
    |> Translations.translate_assoc(:course)
  end

  defp ordered_on(order), do: helsinki_date(order.ordered_at || order.inserted_at)

  defp helsinki_date(datetime), do: datetime |> DateTime.shift_zone!(@timezone) |> DateTime.to_date()
end

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
     |> assign(orders: Orders.list_my_orders!(actor: user))
     |> assign(subscriptions: subscriptions(user))
     |> assign(edited_subscriptions: MapSet.new())
     |> assign(subscription_notice: nil)
     |> assign_subscription_product()
     |> assign(registrations: registrations(user))
     |> assign(newsletter_form_id: @newsletter_form_id)
     |> assign(newsletter_saved?: false)
     |> assign(newsletter_saved_token: nil)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container class="max-w-3xl">
        <div class="border-base-content/12 flex flex-col gap-4 pb-10 not-last:border-b sm:flex-row sm:items-baseline sm:justify-between sm:pb-12">
          <h1 class="page-title">
            {if @current_user.first_name, do: ~t"Hi, #{@current_user.first_name}", else: ~t"Account"}
          </h1>
          <.button href={~p"/sign-out"} method="delete" variant="neutral" size="sm" class="w-fit">
            {~t"Sign out"}
          </.button>
        </div>

        <section class="border-base-content/12 py-10 not-last:border-b sm:py-14" aria-labelledby="details-heading">
          <h2 id="details-heading" class="section-title">{~t"Your details"}</h2>

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
              <.button type="submit" phx-disable-with={~t"Saving…"}>{~t"Save"}</.button>
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
              <.button type="submit" phx-disable-with={~t"Confirming…"}>{~t"Confirm"}</.button>
              <.button type="button" variant="text" phx-click="cancel_email_change">{~t"Cancel"}</.button>
            </div>
          </.form>
        </section>

        <section class="border-base-content/12 py-10 not-last:border-b sm:py-14" aria-labelledby="orders-heading">
          <h2 id="orders-heading" class="section-title">{~t"Orders"}</h2>

          <div :if={@orders == []} class="mt-6">
            <p class="text-base-content/80">{~t"You haven't ordered anything yet."}</p>
            <.button navigate={~p"/store"} variant="text" class="mt-4">{~t"Visit the shop"}</.button>
          </div>

          <%!-- table-fixed, or a long status pushes the whole document wider than a phone. --%>
          <table
            :if={@orders != []}
            class="mt-8 w-full table-fixed text-left text-sm sm:text-base"
            data-testid="orders-table"
          >
            <thead>
              <tr class="text-base-content/70">
                <th scope="col" class="eyebrow w-2/5 pr-4 pb-3 sm:w-1/6">{~t"Date"}</th>
                <th scope="col" class="eyebrow hidden pr-4 pb-3 sm:table-cell sm:w-1/6">{~t"Reference"}</th>
                <th scope="col" class="eyebrow pr-4 pb-3">{~t"Status"}</th>
                <th scope="col" class="eyebrow w-1/5 pb-3 text-right sm:w-1/6 sm:pr-4">{~t"Total"}</th>
                <th scope="col" class="w-[13%] hidden pb-3 sm:table-cell">
                  <span class="sr-only">{~t"Receipt"}</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={order <- @orders} class="border-base-content/12 border-t align-top">
                <th scope="row" class="py-4 pr-4 font-normal">
                  <span class="tabular-nums">{Format.date(ordered_on(order), @locale)}</span>
                  <%!-- Below sm neither the reference nor the receipt has a column of its
                       own; both ride under the date. --%>
                  <span class="text-base-content/70 block text-xs tabular-nums sm:hidden">
                    {order.order_reference}
                  </span>
                  <.receipt_link
                    :if={order.payment_status == :paid}
                    href={~p"/order/#{order.id}/receipt"}
                    class="mt-1 sm:hidden"
                  />
                </th>
                <td class="hidden py-4 pr-4 tabular-nums sm:table-cell">{order.order_reference}</td>
                <td class="py-4 pr-4">
                  {status_label(order, @locale)}
                  <span
                    :if={order.subscription_id}
                    class="text-base-content/70 block text-sm"
                    data-testid="order-subscription"
                  >
                    {~t"Subscription"}
                  </span>
                  <.unpaid_note :if={order.unpaid?} order={order} />
                </td>
                <%!-- Sans, not serif: Crimson Text ships no `tnum`, so a serif total
                      cannot line up its decimal points down a ledger column. --%>
                <td class="py-4 text-right tabular-nums sm:pr-4">
                  {Format.currency(order.grand_total, @locale)}
                </td>
                <td class="hidden py-4 text-right sm:table-cell">
                  <.receipt_link :if={order.payment_status == :paid} href={~p"/order/#{order.id}/receipt"} />
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <section class="border-base-content/12 py-10 not-last:border-b sm:py-14" aria-labelledby="subscriptions-heading">
          <h2 id="subscriptions-heading" class="section-title">{~t"Subscriptions"}</h2>

          <div :if={@subscriptions == []} class="mt-6" data-testid="no-subscriptions">
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

          <table
            :if={@subscriptions != []}
            class="mt-8 w-full table-fixed text-left text-sm sm:text-base"
            data-testid="subscriptions-table"
          >
            <thead>
              <tr class="text-base-content/70">
                <%!-- Widths match the Orders table above, so the two read as one ledger. --%>
                <th scope="col" class="eyebrow w-2/5 pr-4 pb-3 sm:w-1/3">{~t"Plan"}</th>
                <th scope="col" class="eyebrow pr-4 pb-3">{~t"Next delivery"}</th>
                <th scope="col" class="eyebrow hidden w-1/6 pb-3 text-right sm:table-cell sm:pr-4">{~t"Price"}</th>
                <th scope="col" class="w-[13%] hidden pb-3 sm:table-cell">
                  <span class="sr-only">{~t"Manage"}</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={subscription <- @subscriptions}
                id={"subscription-#{subscription.id}"}
                class="border-base-content/12 border-t align-top"
              >
                <th scope="row" class="py-4 pr-4 font-normal">
                  <span id={"subscription-#{subscription.id}-name"}>{subscription_name(subscription)}</span>
                  <span class="text-base-content/70 block text-xs sm:text-sm">{plan_label(subscription)}</span>
                  <%!-- Below sm neither the price nor Manage has a column of its own;
                       both ride under the name. --%>
                  <span class="text-base-content/70 block text-xs tabular-nums sm:hidden">
                    {~t"#{price = Format.currency(subscription.product_variant.price, @locale)} per delivery"}
                  </span>
                  <.manage_button subscription={subscription} class="mt-1 sm:hidden" />
                </th>
                <td class="py-4 pr-4" data-testid="subscription-status">
                  <.next_delivery subscription={subscription} orders={@orders} locale={@locale} />
                </td>
                <td class="hidden py-4 text-right tabular-nums sm:table-cell sm:pr-4">
                  {Format.currency(subscription.product_variant.price, @locale)}
                </td>
                <td class="hidden py-4 text-right sm:table-cell">
                  <.manage_button subscription={subscription} />
                </td>
              </tr>
            </tbody>
          </table>

          <.manage_drawer
            :for={subscription <- @subscriptions}
            subscription={subscription}
            orders={@orders}
            locale={@locale}
            edited?={subscription.id in @edited_subscriptions}
            notice={notice_for(@subscription_notice, subscription)}
          />
        </section>

        <section class="border-base-content/12 py-10 not-last:border-b sm:py-14" aria-labelledby="courses-heading">
          <h2 id="courses-heading" class="section-title">{~t"Courses"}</h2>

          <div :if={@registrations == []} class="mt-6">
            <p class="text-base-content/80">{~t"You haven't booked a course yet."}</p>
            <.button navigate={~p"/courses"} variant="text" class="mt-4">{~t"See what's coming up"}</.button>
          </div>

          <table
            :if={@registrations != []}
            class="mt-8 w-full table-fixed text-left text-sm sm:text-base"
            data-testid="courses-table"
          >
            <thead>
              <tr class="text-base-content/70">
                <th scope="col" class="eyebrow pr-4 pb-3">{~t"Course"}</th>
                <th scope="col" class="eyebrow hidden pr-4 pb-3 sm:table-cell sm:w-1/4">{~t"Location"}</th>
                <th scope="col" class="eyebrow w-1/4 pr-4 pb-3 sm:w-1/6">{~t"When"}</th>
                <th scope="col" class="eyebrow w-1/5 pb-3 text-right sm:w-[10%] sm:pr-4">{~t"Places"}</th>
                <th scope="col" class="w-[13%] hidden pb-3 sm:table-cell">
                  <span class="sr-only">{~t"Receipt"}</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={registration <- @registrations} class="border-base-content/12 border-t align-top">
                <th scope="row" class="py-4 pr-4 font-normal">
                  <.link navigate={~p"/courses/#{registration.course.id}"} class="link-underline-hover">
                    {registration.course.name}
                  </.link>
                  <%!-- Below sm neither the location nor the receipt has a column of its
                       own; both ride under the name. --%>
                  <span class="text-base-content/70 block text-xs sm:hidden">
                    {registration.course.location_name}
                  </span>
                  <.receipt_link href={~p"/courses/bookings/#{registration.id}/receipt"} class="mt-1 sm:hidden" />
                </th>
                <td class="hidden py-4 pr-4 sm:table-cell">{registration.course.location_name}</td>
                <td class="py-4 pr-4 tabular-nums">
                  {Format.day_month(registration.course.date, @locale)}
                  <span class="text-base-content/70 block text-xs tabular-nums sm:text-sm">
                    {Format.time(registration.course.start_time, @locale)}
                  </span>
                </td>
                <td class="py-4 text-right tabular-nums sm:pr-4">{registration.seats_held}</td>
                <td class="hidden py-4 text-right sm:table-cell">
                  <.receipt_link href={~p"/courses/bookings/#{registration.id}/receipt"} />
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <section class="border-base-content/12 py-10 not-last:border-b sm:py-14" aria-labelledby="newsletter-heading">
          <h2 id="newsletter-heading" class="section-title">{~t"Newsletter"}</h2>

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
        </section>
      </.container>
    </Layouts.app>
    """
  end

  attr :href, :string, required: true
  attr :class, :string, default: nil

  defp receipt_link(assigns) do
    ~H"""
    <.button
      href={@href}
      target="_blank"
      rel="noopener"
      aria-label={~t"Receipt (opens in a new tab)"}
      variant="neutral"
      size="sm"
      class={["whitespace-nowrap", @class]}
    >
      {~t"Receipt"}
    </.button>
    """
  end

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

    assign(socket, subscriptions: subscriptions(user), orders: Orders.list_my_orders!(actor: user))
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

  defp cancel_dialog(assigns) do
    assigns = assign(assigns, final_delivery?: final_delivery?(assigns.booked))

    ~H"""
    <dialog
      id={"cancel-subscription-#{@subscription.id}"}
      autofocus
      class="modal outline-hidden"
      aria-labelledby={"cancel-subscription-#{@subscription.id}-title"}
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <div class="modal-box bg-base-100 rounded-none">
        <h3 id={"cancel-subscription-#{@subscription.id}-title"} class="font-serif text-2xl">
          {~t"Stop your subscription?"}
        </h3>
        <p :if={@final_delivery?} class="mt-3" data-testid="final-delivery-warning">
          {~t"Your delivery on #{date = Format.weekday_date(@booked.fulfillment_date, @locale)} is already being prepared and will be your final delivery. There will be no deliveries or charges after that."}
        </p>
        <p :if={not @final_delivery?} class="mt-3">{~t"There will be no more deliveries or charges."}</p>
        <p :if={@subscription.state == :active} class="mt-2">
          {~t"Want a break instead?"}
          <.button
            type="button"
            variant="text"
            phx-click={
              JS.push("pause_subscription", value: %{id: @subscription.id})
              |> JS.dispatch("drawer:close", to: "#cancel-subscription-#{@subscription.id}")
            }
          >
            {~t"Pause it"}
          </.button>
        </p>
        <div class="mt-6 flex flex-wrap gap-3">
          <form method="dialog">
            <.button type="submit" variant="primary" autofocus>{~t"Keep it"}</.button>
          </form>
          <.button
            type="button"
            variant="destructive"
            phx-click={
              JS.push("cancel_subscription", value: %{id: @subscription.id})
              |> JS.dispatch("drawer:close", to: "#cancel-subscription-#{@subscription.id}")
            }
          >
            {~t"Stop subscription"}
          </.button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button type="submit">{~t"Close"}</button>
      </form>
    </dialog>
    """
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
  attr :class, :string, default: nil

  defp manage_button(assigns) do
    ~H"""
    <.button
      type="button"
      variant="neutral"
      size="sm"
      class={["whitespace-nowrap", @class]}
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

  # The table's short form: the date, then one line on what's happening.
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
              :if={@open? and @subscription.state in [:active, :paused]}
              role="group"
              aria-label={~t"Deliveries"}
              class="mt-4 flex flex-wrap gap-3"
            >
              <%!-- One id for both, so the button is patched in place and keeps focus. --%>
              <.button
                id={"subscription-#{@id}-pause"}
                type="button"
                variant={if @subscription.state == :paused, do: "primary", else: "secondary"}
                phx-click={if @subscription.state == :active, do: "pause_subscription", else: "resume_subscription"}
                phx-value-id={@id}
              >
                {if @subscription.state == :active, do: ~t"Pause", else: ~t"Resume"}
              </.button>
            </div>

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
                variant="secondary"
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
              <p data-testid="subscription-card">{Fields.card_label(@subscription) || ~t"Saved card"}</p>
              <.link
                navigate={~p"/account/subscriptions/#{@id}/card"}
                class="link-underline-static-body min-h-11 inline-flex shrink-0 items-center"
              >
                {~t"Update card"}
              </.link>
            </div>
          </.detail_row>
        </dl>

        <.button
          :if={@subscription.state != :cancelled}
          type="button"
          variant="text"
          class="text-base-content/70 min-h-11 mt-auto self-start"
          phx-click={JS.dispatch("drawer:open", to: "#cancel-subscription-#{@id}")}
        >
          {~t"Cancel subscription"}
        </.button>

        <.cancel_dialog
          :if={@subscription.state != :cancelled}
          subscription={@subscription}
          booked={@booked}
          locale={@locale}
        />
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
  Plain-language order status for the customer.

  Never claims an outcome the data doesn't support: an order whose fulfillment
  date has passed but which Jennie hasn't marked fulfilled shows the date it was
  scheduled for, not "Delivered".
  """
  def status_label(order, locale)

  def status_label(%{payment_status: :refunded}, _locale), do: ~t"Refunded"

  def status_label(%{fulfillment_status: :cancelled}, _locale), do: ~t"Cancelled"

  def status_label(%{fulfillment_date: nil}, _locale), do: ~t"Confirmed"

  def status_label(%{fulfillment_status: :fulfilled} = order, locale) do
    date = Format.day_month(order.fulfillment_date, locale)

    case order.fulfillment_method do
      :pickup -> ~t"Collected #{date}"
      _ -> ~t"Delivered #{date}"
    end
  end

  def status_label(order, locale) do
    date = Format.day_month(order.fulfillment_date, locale)

    case {Date.compare(order.fulfillment_date, HelsinkiToday.today()), order.fulfillment_method} do
      {:eq, :pickup} -> ~t"Ready to collect today"
      {:eq, _} -> ~t"Arriving today"
      {:gt, :pickup} -> ~t"Ready to collect #{date}"
      {:gt, _} -> ~t"Arriving #{date}"
      {:lt, :pickup} -> ~t"Pickup on #{date}"
      {:lt, _} -> ~t"Delivery on #{date}"
    end
  end

  defp registrations(user) do
    Courses.list_my_registrations!(actor: user, load: [:course, :seats_held])
    |> Translations.translate_assoc(:course)
    |> Enum.sort_by(& &1.course.date, Date)
  end

  defp ordered_on(order), do: helsinki_date(order.ordered_at || order.inserted_at)

  defp helsinki_date(datetime), do: datetime |> DateTime.shift_zone!(@timezone) |> DateTime.to_date()
end

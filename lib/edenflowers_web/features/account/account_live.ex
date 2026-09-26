defmodule EdenflowersWeb.Account.AccountLive do
  use EdenflowersWeb, :live_view

  require Logger

  alias Edenflowers.Accounts
  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_required}

  @timezone "Europe/Helsinki"
  @saved_visible_ms 2500
  @newsletter_form_id "newsletter-preference"

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(page_title: ~t"Account")
     |> assign(locale: Format.locale())
     |> assign(orders: Orders.list_my_orders!(actor: user))
     |> assign(registrations: registrations(user))
     |> assign(newsletter_form_id: @newsletter_form_id)
     |> assign(newsletter_saved?: false)
     |> assign(newsletter_saved_token: nil)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container class="max-w-3xl">
        <h1 class="page-title">{~t"Account"}</h1>

        <div class="border-base-content/12 mt-8 flex flex-col gap-4 pb-10 not-last:border-b sm:flex-row sm:items-baseline sm:justify-between sm:pb-12">
          <div>
            <p :if={@current_user.name} class="font-serif text-2xl leading-snug">{@current_user.name}</p>
            <p class="text-base-content/70 text-sm">{@current_user.email}</p>
          </div>
          <.link href={~p"/sign-out"} method="delete" class="link-underline-hover -my-1.5 w-fit py-1.5 text-sm">
            {~t"Sign out"}
          </.link>
        </div>

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
                    class="mt-1 block sm:hidden"
                  />
                </th>
                <td class="hidden py-4 pr-4 tabular-nums sm:table-cell">{order.order_reference}</td>
                <td class="py-4 pr-4">{status_label(order, @locale)}</td>
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
                  <.receipt_link href={~p"/courses/bookings/#{registration.id}/receipt"} class="mt-1 block sm:hidden" />
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
            <label class="flex max-w-prose cursor-pointer items-start gap-3">
              <input type="hidden" name="newsletter_opt_in" value="false" />
              <input
                type="checkbox"
                name="newsletter_opt_in"
                value="true"
                checked={@current_user.newsletter_subscribed?}
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
    <.link
      href={@href}
      target="_blank"
      rel="noopener"
      aria-label={~t"Receipt (opens in a new tab)"}
      class={["link-underline-hover whitespace-nowrap py-1.5", @class]}
    >
      {~t"Receipt"}
    </.link>
    """
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

        # The save failed, so `current_user` is unchanged and nothing inside the
        # form would appear in the diff — LiveView would leave the browser showing
        # the box the customer just ticked. A new form id replaces the subtree,
        # which puts the checkbox back to what the server actually holds.
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

  @doc """
  Plain-language order status for the customer.

  Never claims an outcome the data doesn't support: an order whose fulfillment
  date has passed but which Jennie hasn't marked fulfilled shows the date it was
  scheduled for, not "Delivered".
  """
  def status_label(order, locale)

  def status_label(%{payment_status: :refunded}, _locale), do: ~t"Refunded"

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

    case {Date.compare(order.fulfillment_date, store_today()), order.fulfillment_method} do
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

  defp ordered_on(order) do
    (order.ordered_at || order.inserted_at)
    |> DateTime.shift_zone!(@timezone)
    |> DateTime.to_date()
  end

  defp store_today, do: @timezone |> DateTime.now!() |> DateTime.to_date()
end

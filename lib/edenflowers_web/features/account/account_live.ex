defmodule EdenflowersWeb.Account.AccountLive do
  use EdenflowersWeb, :live_view

  require Logger

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Workers.SendEmailChangeCode
  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.RateLimiter
  alias Edenflowers.Translations

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
          <.link href={~p"/sign-out"} method="delete" class="link-underline-hover -my-1.5 w-fit py-1.5 text-sm">
            {~t"Sign out"}
          </.link>
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
                    class="mt-1 block sm:hidden"
                  />
                </th>
                <td class="hidden py-4 pr-4 tabular-nums sm:table-cell">{order.order_reference}</td>
                <td class="py-4 pr-4">
                  {status_label(order, @locale)}
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

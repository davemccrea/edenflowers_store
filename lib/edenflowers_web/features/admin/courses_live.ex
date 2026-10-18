defmodule EdenflowersWeb.Admin.CoursesLive do
  use EdenflowersWeb, :live_view

  require Logger

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Format
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Courses")
     |> assign(:locale, Localize.get_locale())
     |> assign(booking_form: nil, booking_course_id: nil)
     |> load_courses()}
  end

  # The Overview links here with ?booking= to open that booking's course and point at it.
  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, assign(socket, :highlighted_booking_id, params["booking"])}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Courses"}>
          <:actions>
            <.button navigate={~p"/admin/courses/new"} variant="neutral" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" />
              {~t"New course"}
            </.button>
          </:actions>
        </.admin_page_header>

        <p :if={@courses == []} class="text-base-content/65 py-6 text-center text-sm">
          {~t"No upcoming courses"}
        </p>

        <div class="grid grid-cols-1 items-start gap-4 xl:grid-cols-2">
          <.course
            :for={course <- @courses}
            course={course}
            locale={@locale}
            booking_form={if @booking_course_id == course.id, do: @booking_form}
            highlighted_booking_id={@highlighted_booking_id}
          />
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("new_booking", %{"course-id" => course_id}, socket) do
    form =
      AshPhoenix.Form.for_create(CourseRegistration, :add_manually,
        actor: socket.assigns.current_user,
        transform_params: fn _form, params, _action -> Map.put(params, "course_id", course_id) end
      )
      |> to_form()

    {:noreply, assign(socket, booking_form: form, booking_course_id: course_id)}
  end

  def handle_event("close_booking", _params, socket) do
    {:noreply, assign(socket, booking_form: nil, booking_course_id: nil)}
  end

  def handle_event("validate_booking", %{"form" => params}, socket) do
    {:noreply, assign(socket, :booking_form, AshPhoenix.Form.validate(socket.assigns.booking_form, params))}
  end

  def handle_event("save_booking", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.booking_form, params: params) do
      {:ok, _registration} ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Booking added.")
         |> assign(booking_form: nil, booking_course_id: nil)
         |> load_courses()}

      {:error, form} ->
        {:noreply, assign(socket, :booking_form, form)}
    end
  end

  @impl true
  def handle_event("mark_paid", %{"registration_id" => id, "payment_method" => payment_method}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor, load: [:balance]),
           {:ok, _} <-
             Courses.record_registration_payment(registration, registration.balance, payment_method, actor: actor) do
        put_flash(socket, :info, ~t"Payment recorded.")
      else
        _ -> put_flash(socket, :error, ~t"Could not record the payment.")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("record_payment", %{"record_id" => id, "payment" => params}, socket) do
    actor = socket.assigns.current_user
    amount = String.replace(params["amount"], ",", ".")

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.record_registration_payment(registration, amount, params["payment_method"], actor: actor) do
        put_flash(socket, :info, ~t"Payment recorded.")
      else
        {:error, error} -> put_flash(socket, :error, payment_error(error))
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("undo_payment", %{"id" => id, "payment-id" => payment_id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.undo_registration_payment(registration, payment_id, actor: actor) do
        put_flash(socket, :info, ~t"Payment undone.")
      else
        _ -> put_flash(socket, :error, ~t"Could not undo the payment.")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("refund_with_stripe", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, refunds} <- Edenflowers.Payments.refund_balance(registration) do
        put_flash(socket, :info, refund_message(refunds))
      else
        error ->
          Logger.error("Stripe refund for course registration #{id} failed: #{inspect(error)}")
          put_flash(socket, :error, ~t"Could not refund with Stripe. Check the payment in Stripe.")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("open_payment_link", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.open_registration_payment_link(registration, actor: actor) do
        put_flash(socket, :info, ~t"Payment link created.")
      else
        _ -> put_flash(socket, :error, ~t"Could not create a payment link.")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("email_payment_link", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.email_registration_payment_link(registration, actor: actor) do
        put_flash(socket, :info, ~t"Payment link emailed.")
      else
        _ -> put_flash(socket, :error, ~t"Could not email the payment link.")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("payment_link_copied", _params, socket) do
    {:noreply, put_flash(socket, :info, ~t"Payment link copied.")}
  end

  def handle_event("remove_seat", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.remove_registration_seat(registration, actor: actor) do
        put_flash(socket, :info, ~t"Seat removed.")
      else
        _ -> put_flash(socket, :error, ~t"Could not remove the seat.")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.cancel_registration(registration, actor: actor) do
        put_flash(socket, :info, ~t"Booking cancelled.")
      else
        _ -> put_flash(socket, :error, ~t"Could not cancel the booking.")
      end

    {:noreply, load_courses(socket)}
  end

  defp load_courses(socket) do
    courses =
      Courses.list_admin_courses!(
        actor: socket.assigns.current_user,
        load: [
          bookings: [
            :amount_paid,
            :balance,
            :settled?,
            :outside_stripe_refund,
            :stripe_refund,
            :seats_held,
            :payment_link_open?,
            payments: [:undoable?]
          ]
        ]
      )

    assign(socket, :courses, courses)
  end

  attr :course, :map, required: true
  attr :locale, :any, required: true
  attr :booking_form, :any, required: true
  attr :highlighted_booking_id, :string, default: nil

  defp course(assigns) do
    {registrations, cancelled} = Enum.split_with(assigns.course.bookings, &(&1.status == :confirmed))

    assigns =
      assigns
      |> assign(:cancelled, cancelled)
      |> assign(:registrations, registrations)
      |> assign(:seats, Enum.sum_by(registrations, & &1.seats_held))
      |> assign(:still_to_pay, Enum.count(registrations, &to_collect?/1))
      |> assign(:past?, Date.before?(assigns.course.date, Edenflowers.ShopTime.today()))
      |> assign(:bcc, registrations |> Enum.map(& &1.email) |> Enum.uniq() |> Enum.join(","))

    ~H"""
    <details
      id={"course-#{@course.id}"}
      open={Enum.any?(@course.bookings, &(&1.id == @highlighted_booking_id))}
      phx-mounted={JS.ignore_attributes(["open"])}
      class="admin-card group"
    >
      <summary class="list-none p-4 sm:p-5">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h2 class="text-base-content font-semibold">
              {@course.name}
              <.badge :if={@past?} tone={:tag} class="ml-1 align-middle">{pgettext("course", "Past")}</.badge>
            </h2>
            <p class="text-base-content/65 text-sm">
              {Format.weekday_date(@course.date, @locale)}, {Format.time(@course.start_time, @locale)}–{Format.time(
                @course.end_time,
                @locale
              )}
            </p>
          </div>
          <.icon
            name="hero-chevron-down"
            class="text-base-content/50 h-5 w-5 shrink-0 transition-transform group-open:rotate-180"
          />
        </div>
        <div class="mt-3 flex items-center gap-3 text-sm tabular-nums">
          <progress class="progress progress-primary w-full" value={@seats} max={@course.total_places} />
          <span class="whitespace-nowrap">{~t"#{@seats} / #{total = @course.total_places} seats"}</span>
        </div>
      </summary>

      <div class="border-base-content/12 border-t p-4 sm:p-5">
        <p :if={@registrations == []} class="text-base-content/65 mb-4 text-sm">{~t"No bookings yet"}</p>
        <p :if={@still_to_pay > 0} class="text-base-content/65 mb-4 text-sm">
          {~t"#{count = @still_to_pay} to collect"}
        </p>

        <div class="mb-4 flex flex-wrap gap-2">
          <.button
            :if={@registrations != []}
            href={fastmail_compose(bcc: @bcc)}
            target="_blank"
            rel="noopener"
            variant="neutral"
            size="sm"
          >
            <.icon name="hero-envelope" class="h-4 w-4" />
            {~t"Email everyone"}
          </.button>
          <.button
            :if={is_nil(@booking_form)}
            type="button"
            phx-click="new_booking"
            phx-value-course-id={@course.id}
            variant="neutral"
            size="sm"
          >
            <.icon name="hero-plus" class="h-4 w-4" />
            {~t"Add booking"}
          </.button>
          <.button navigate={~p"/admin/courses/#{@course.id}"} variant="ghost" size="sm">
            <.icon name="hero-pencil-square" class="h-4 w-4" />
            {~t"Edit course"}
          </.button>
        </div>

        <.form
          :if={@booking_form}
          for={@booking_form}
          id={"booking-form-#{@course.id}"}
          phx-change="validate_booking"
          phx-submit="save_booking"
          class="bg-base-200/50 mb-4 space-y-3 p-4"
        >
          <.input field={@booking_form[:name]} type="text" label={~t"Name"} class="input w-full" />
          <.input field={@booking_form[:email]} type="email" label={~t"Email"} class="input w-full" />
          <div class="grid grid-cols-2 gap-3">
            <.input
              field={@booking_form[:seats]}
              type="number"
              label={~t"Seats"}
              min="1"
              max={CourseRegistration.max_seats()}
              class="input w-full"
            />
            <.input
              field={@booking_form[:locale]}
              type="select"
              label={~t"Language"}
              options={[{"Svenska", "sv-FI"}, {"Suomi", "fi"}, {"English", "en-GB"}]}
            />
          </div>
          <p class="text-base-content/65 text-sm">
            {~t"They'll get a confirmation email. Payment is taken at the course."}
          </p>
          <div class="flex gap-2">
            <.button type="submit" variant="primary" size="sm">{~t"Add booking"}</.button>
            <.button type="button" phx-click="close_booking" variant="ghost" size="sm">{~t"Close"}</.button>
          </div>
        </.form>

        <ul class="divide-base-content/12 divide-y">
          <li
            :for={registration <- @registrations}
            id={"registration-#{registration.id}"}
            aria-current={registration.id == @highlighted_booking_id && "true"}
            class={["py-2.5", registration.id == @highlighted_booking_id && highlighted_row_class()]}
          >
            <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
              <div class="min-w-48 flex-1">
                <p class="text-base-content truncate font-medium">
                  {registration.name}
                  <span :if={registration.seats_held > 1} class="text-base-content/65 tabular-nums">
                    +{registration.seats_held - 1}
                  </span>
                  <.badge :if={to_collect?(registration)} tone={:warning} class="ml-1 align-middle">
                    {~t"To collect"}
                  </.badge>
                </p>
                <a
                  href={fastmail_compose(to: registration.email)}
                  target="_blank"
                  rel="noopener"
                  class="text-base-content/65 truncate text-sm pointer-coarse:py-3 hover:underline"
                >
                  {registration.email}
                </a>
              </div>
              <div class="flex w-full items-center justify-end gap-1 sm:ml-auto sm:w-auto sm:shrink-0">
                <%!-- Recording a payment stays out of the menu: it's what the florist taps at the course itself. --%>
                <form
                  :if={to_collect?(registration)}
                  id={"mark-paid-#{registration.id}"}
                  phx-submit="mark_paid"
                  class="flex flex-1 items-center gap-1 sm:flex-none"
                >
                  <input type="hidden" name="registration_id" value={registration.id} />
                  <label for={"mark-paid-method-#{registration.id}"} class="sr-only">{~t"How"}</label>
                  <select
                    id={"mark-paid-method-#{registration.id}"}
                    name="payment_method"
                    class="select select-sm flex-1 sm:w-auto sm:flex-none"
                  >
                    {Phoenix.HTML.Form.options_for_select(payment_method_options(), :zettle)}
                  </select>
                  <.button type="submit" variant="neutral" size="sm">{~t"Record payment"}</.button>
                </form>
                <.actions_menu id={"registration-actions-#{registration.id}"}>
                  <li :if={stripe_payment_intent_id(registration)}>
                    <.link
                      href={StripeAPI.dashboard_payment_url(stripe_payment_intent_id(registration))}
                      target="_blank"
                      rel="noopener"
                    >
                      Stripe <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                    </.link>
                  </li>
                  <.actions_menu_button
                    :if={to_collect?(registration)}
                    menu={"registration-actions-#{registration.id}"}
                    phx-click="email_payment_link"
                    phx-value-id={registration.id}
                    data-confirm={email_payment_link_confirmation(registration, @locale)}
                  >
                    {if payment_link_emailed?(registration),
                      do: ~t"Resend payment link",
                      else: ~t"Email payment link"}
                  </.actions_menu_button>
                  <.actions_menu_button
                    :if={to_collect?(registration) and registration.payment_link_open?}
                    id={"copy-payment-link-#{registration.id}"}
                    menu={"registration-actions-#{registration.id}"}
                    phx-click={
                      JS.dispatch("edenflowers:copy", to: "#payment-link-url-#{registration.id}")
                      |> JS.push("payment_link_copied")
                    }
                  >
                    {~t"Copy payment link"}
                    <span id={"payment-link-url-#{registration.id}"} hidden>
                      {EdenflowersWeb.PaymentLink.url_for(registration)}
                    </span>
                  </.actions_menu_button>
                  <.actions_menu_button
                    :if={to_collect?(registration) and not registration.payment_link_open?}
                    menu={"registration-actions-#{registration.id}"}
                    phx-click="open_payment_link"
                    phx-value-id={registration.id}
                  >
                    {~t"Create payment link"}
                  </.actions_menu_button>
                  <.actions_menu_button
                    :for={payment <- registration.payments}
                    :if={payment.undoable?}
                    id={"undo-payment-#{payment.id}"}
                    menu={"registration-actions-#{registration.id}"}
                    phx-click="undo_payment"
                    phx-value-id={registration.id}
                    phx-value-payment-id={payment.id}
                    data-confirm={undo_confirmation(payment, @locale)}
                  >
                    {undo_label(payment, @locale)}
                  </.actions_menu_button>
                  <.actions_menu_button
                    :if={registration.seats_held > 1}
                    menu={"registration-actions-#{registration.id}"}
                    phx-click="remove_seat"
                    phx-value-id={registration.id}
                    data-confirm={remove_seat_confirmation(registration)}
                  >
                    {~t"Remove a seat"}
                  </.actions_menu_button>
                  <.actions_menu_button
                    menu={"registration-actions-#{registration.id}"}
                    phx-click="cancel"
                    phx-value-id={registration.id}
                    data-confirm={cancel_confirmation(registration)}
                    class="text-error"
                  >
                    {pgettext("course booking", "Cancel")}
                  </.actions_menu_button>
                </.actions_menu>
              </div>
            </div>
            <%!-- Only a refund gets the whole panel: collecting is the quick form above. --%>
            <.balance_panel
              :if={Decimal.negative?(registration.balance)}
              id={"balance-#{registration.id}"}
              record={registration}
              locale={@locale}
              class="mt-3"
            />
          </li>
          <li
            :for={registration <- @cancelled}
            id={"registration-#{registration.id}"}
            data-status="cancelled"
            aria-current={registration.id == @highlighted_booking_id && "true"}
            class={["text-base-content/50 py-2.5", registration.id == @highlighted_booking_id && highlighted_row_class()]}
          >
            <p class="truncate line-through">
              {registration.name}
              <span :if={registration.seats_held > 1} class="tabular-nums">+{registration.seats_held - 1}</span>
            </p>
            <p class="truncate text-sm">{registration.email}</p>
            <.balance_panel id={"balance-#{registration.id}"} record={registration} locale={@locale} class="mt-3" />
          </li>
        </ul>
      </div>
    </details>
    """
  end

  # A paid booking's PaymentIntent is on its Payment; a pending one's is still on the booking.
  defp stripe_payment_intent_id(registration),
    do: Enum.find_value(registration.payments, & &1.payment_intent_id) || registration.payment_intent_id

  defp to_collect?(registration), do: not registration.settled? and Decimal.positive?(registration.balance)

  defp highlighted_row_class, do: "row-flash scroll-mt-[calc(env(safe-area-inset-top)+6rem)]"

  defp undo_label(payment, locale) do
    amount = Format.currency(Decimal.abs(payment.amount), locale)

    if Decimal.negative?(payment.amount),
      do: ~t"Undo #{amount} refund",
      else: ~t"Undo #{amount} payment"
  end

  defp payment_link_emailed?(registration),
    do: registration.payment_link_open? and not is_nil(registration.payment_link_emailed_at)

  defp email_payment_link_confirmation(registration, locale) do
    question = ~t"Email a payment link to #{email = registration.email}?"

    if payment_link_emailed?(registration),
      do: ~t"Last sent #{time = Format.datetime(registration.payment_link_emailed_at, locale)}." <> " " <> question,
      else: question
  end

  defp paid?(registration), do: Decimal.positive?(registration.amount_paid)

  defp remove_seat_confirmation(registration) do
    if paid?(registration) do
      ~t"This does not refund. Refund the seat here afterwards. Remove one seat from this booking?"
    else
      ~t"Remove one seat from this booking?"
    end
  end

  defp cancel_confirmation(registration) do
    if paid?(registration) do
      ~t"This frees the seats but does not refund. Refund here afterwards. Cancel this booking?"
    else
      ~t"This frees the seats. Cancel this booking?"
    end
  end

  # Jennie uses Fastmail on the web, so compose there rather than via mailto:.
  defp fastmail_compose(params), do: "https://app.fastmail.com/mail/compose?" <> URI.encode_query(params)
end

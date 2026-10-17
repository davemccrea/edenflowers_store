defmodule EdenflowersWeb.Admin.CoursesLive do
  use EdenflowersWeb, :live_view

  require Logger

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Payments.PaymentMethod
  alias EdenflowersWeb.Admin.OrderLog

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
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.mark_registration_paid(registration, payment_method, actor: actor) do
        put_flash(socket, :info, ~t"Booking marked as paid.")
      else
        _ -> put_flash(socket, :error, ~t"Could not mark the booking as paid.")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event(
        "record_in_person_refund",
        %{"registration_id" => id, "payment_method" => payment_method, "amount" => amount},
        socket
      ) do
    actor = socket.assigns.current_user
    amount = String.replace(amount, ",", ".")

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <-
             Courses.record_registration_in_person_refund(registration, amount, payment_method, actor: actor) do
        put_flash(socket, :info, ~t"Refund recorded.")
      else
        _ -> put_flash(socket, :error, ~t"Could not record the refund. Check the amount.")
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
          put_flash(socket, :error, ~t"Could not refund through Stripe. Check the payment in Stripe.")
      end

    {:noreply, load_courses(socket)}
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
      Courses.list_upcoming_courses!(
        actor: socket.assigns.current_user,
        load: [bookings: [:balance, :amount_paid, :in_person_paid, :seats_held]]
      )

    assign(socket, :courses, courses)
  end

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
          />
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :course, :map, required: true
  attr :locale, :any, required: true
  attr :booking_form, :any, required: true

  defp course(assigns) do
    {registrations, cancelled} = Enum.split_with(assigns.course.bookings, &(&1.status == :confirmed))

    assigns =
      assigns
      |> assign(:cancelled, cancelled)
      |> assign(:registrations, registrations)
      |> assign(:seats, Enum.sum_by(registrations, & &1.seats_held))
      |> assign(:still_to_pay, Enum.count(registrations, &owes?/1))
      |> assign(:bcc, registrations |> Enum.map(& &1.email) |> Enum.uniq() |> Enum.join(","))

    ~H"""
    <details
      id={"course-#{@course.id}"}
      phx-mounted={JS.ignore_attributes(["open"])}
      class="admin-card group"
    >
      <summary class="list-none p-4 sm:p-5">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h2 class="text-base-content font-semibold">{@course.name}</h2>
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
          {~t"#{count = @still_to_pay} still to pay at the course"}
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
          <li :for={registration <- @registrations} class="flex items-center gap-3 py-2.5">
            <div class="min-w-0 flex-1">
              <p class="text-base-content truncate font-medium">
                {registration.name}
                <span :if={registration.seats_held > 1} class="text-base-content/65 tabular-nums">
                  +{registration.seats_held - 1}
                </span>
                <.badge :if={owes?(registration)} tone={:warning} class="ml-1 align-middle">
                  {~t"Pays at course"}
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
              <.refund_in_person :if={refundable_in_person?(registration)} registration={registration} />
              <.refund_with_stripe :if={refundable_with_stripe?(registration)} registration={registration} locale={@locale} />
            </div>
            <div class="flex shrink-0 items-center gap-1">
              <%!-- Mark paid stays out of the menu: it's what the florist taps at the course itself. --%>
              <form
                :if={owes?(registration)}
                id={"mark-paid-#{registration.id}"}
                phx-submit="mark_paid"
                class="flex items-center gap-1"
              >
                <input type="hidden" name="registration_id" value={registration.id} />
                <label for={"mark-paid-method-#{registration.id}"} class="sr-only">{~t"How"}</label>
                <select
                  id={"mark-paid-method-#{registration.id}"}
                  name="payment_method"
                  class="select select-sm w-auto"
                >
                  {Phoenix.HTML.Form.options_for_select(in_person_method_options(), :zettle)}
                </select>
                <.button type="submit" variant="neutral" size="sm">{~t"Mark paid"}</.button>
              </form>
              <.actions_menu id={"registration-actions-#{registration.id}"}>
                <li :if={registration.payment_intent_id}>
                  <.link
                    href={StripeAPI.dashboard_payment_url(registration.payment_intent_id)}
                    target="_blank"
                    rel="noopener"
                  >
                    Stripe <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                  </.link>
                </li>
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
          </li>
          <li :for={registration <- @cancelled} data-status="cancelled" class="text-base-content/50 py-2.5">
            <p class="truncate line-through">
              {registration.name}
              <span :if={registration.seats_held > 1} class="tabular-nums">+{registration.seats_held - 1}</span>
            </p>
            <p class="truncate text-sm">{registration.email}</p>
            <.refund_in_person :if={refundable_in_person?(registration)} registration={registration} />
            <.refund_with_stripe :if={refundable_with_stripe?(registration)} registration={registration} locale={@locale} />
          </li>
        </ul>
      </div>
    </details>
    """
  end

  attr :registration, :map, required: true

  # Money taken at the course goes back in person, up to what was taken that way.
  defp refund_in_person(assigns) do
    ~H"""
    <form
      id={"refund-in-person-#{@registration.id}"}
      phx-submit="record_in_person_refund"
      class="text-base-content mt-2 flex flex-wrap items-center gap-1"
    >
      <input type="hidden" name="registration_id" value={@registration.id} />
      <label for={"refund-method-#{@registration.id}"} class="sr-only">{~t"How"}</label>
      <select id={"refund-method-#{@registration.id}"} name="payment_method" class="select select-sm w-auto">
        {Phoenix.HTML.Form.options_for_select(in_person_method_options(), :zettle)}
      </select>
      <label for={"refund-amount-#{@registration.id}"} class="sr-only">{~t"Amount (€)"}</label>
      <input
        id={"refund-amount-#{@registration.id}"}
        type="text"
        inputmode="decimal"
        name="amount"
        value={Decimal.to_string(in_person_refund(@registration), :normal)}
        class="input input-sm w-24 tabular-nums"
      />
      <.button
        type="submit"
        variant="neutral"
        size="sm"
        data-confirm={~t"Record this refund? It can't be removed, only offset by recording the opposite amount."}
      >
        {~t"Record refund"}
      </.button>
    </form>
    """
  end

  attr :registration, :map, required: true
  attr :locale, :any, required: true

  defp refund_with_stripe(assigns) do
    ~H"""
    <.button
      id={"refund-with-stripe-#{@registration.id}"}
      type="button"
      phx-click="refund_with_stripe"
      phx-value-id={@registration.id}
      phx-disable-with={~t"Refunding…"}
      data-confirm={
        ~t"Refund #{amount = Format.currency(stripe_refund(@registration), @locale)} to the customer's card through Stripe?"
      }
      variant="neutral"
      size="sm"
      class="mt-2"
    >
      {~t"Refund with Stripe"}
    </.button>
    """
  end

  defp refund_message([]), do: ~t"Nothing left to refund. Stripe already has refunds covering it."

  defp refund_message(refunds) do
    if Enum.all?(refunds, &(&1.status == "succeeded")),
      do: ~t"Refunded through Stripe.",
      else: ~t"Refund sent to Stripe. It shows here once it goes through."
  end

  defp owes?(registration), do: Decimal.positive?(registration.balance)

  defp refundable_in_person?(registration),
    do: Decimal.negative?(registration.balance) and Decimal.positive?(registration.in_person_paid)

  defp refundable_with_stripe?(registration),
    do: Decimal.negative?(registration.balance) and Decimal.positive?(stripe_paid(registration))

  defp stripe_paid(registration), do: Decimal.sub(registration.amount_paid, registration.in_person_paid)

  # What the Stripe refund will send back: the balance, as far as Stripe payments cover it.
  defp stripe_refund(registration) do
    registration.balance |> Decimal.negate() |> Decimal.min(stripe_paid(registration))
  end

  defp in_person_refund(registration) do
    registration.balance |> Decimal.negate() |> Decimal.min(registration.in_person_paid) |> Decimal.negate()
  end

  defp in_person_method_options do
    Enum.map(PaymentMethod.in_person(), &{OrderLog.payment_method_label(&1), &1})
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

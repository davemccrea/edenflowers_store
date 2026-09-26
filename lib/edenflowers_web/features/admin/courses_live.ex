defmodule EdenflowersWeb.Admin.CoursesLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  require Ash.Query

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Courses.Workers.SendCourseConfirmationEmail
  alias Edenflowers.Format
  alias Edenflowers.External.StripeAPI

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
      {:ok, registration} ->
        SendCourseConfirmationEmail.enqueue(%{"course_registration_id" => registration.id})

        {:noreply,
         socket
         |> put_flash(:info, ~t"Booking added")
         |> assign(booking_form: nil, booking_course_id: nil)
         |> load_courses()}

      {:error, form} ->
        {:noreply, assign(socket, :booking_form, form)}
    end
  end

  @impl true
  def handle_event("mark_paid", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.mark_registration_paid(registration, actor: actor) do
        socket
      else
        _ -> put_flash(socket, :error, ~t"Could not mark the booking as paid")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("remove_seat", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.remove_registration_seat(registration, actor: actor) do
        socket
      else
        _ -> put_flash(socket, :error, ~t"Could not remove the seat")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.cancel_registration(registration, actor: actor) do
        put_flash(socket, :info, ~t"Booking cancelled")
      else
        _ -> put_flash(socket, :error, ~t"Could not cancel the booking")
      end

    {:noreply, load_courses(socket)}
  end

  # No pending bookings: an unpaid hold is either still at checkout or
  # abandoned, and neither is someone who is coming. Cancelled ones stay so
  # Jennie can see who dropped out.
  defp load_courses(socket) do
    bookings =
      CourseRegistration
      |> Ash.Query.filter(status in [:confirmed, :cancelled])
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.Query.load([:pays_at_course?, :seats_held])

    courses =
      Courses.list_upcoming_courses!(
        actor: socket.assigns.current_user,
        query: [sort: [date: :asc, start_time: :asc]],
        load: [course_registrations: bookings]
      )

    assign(socket, :courses, courses)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="narrow">
        <.admin_page_header title={~t"Courses"} />

        <p :if={@courses == []} class="text-base-content/65 py-6 text-center text-sm">
          {~t"No upcoming courses"}
        </p>

        <div class="space-y-4">
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
    {registrations, cancelled} = Enum.split_with(assigns.course.course_registrations, &(&1.status == :confirmed))

    assigns =
      assigns
      |> assign(:cancelled, cancelled)
      |> assign(:registrations, registrations)
      |> assign(:seats, Enum.sum_by(registrations, & &1.seats_held))
      |> assign(:still_to_pay, Enum.count(registrations, & &1.pays_at_course?))
      |> assign(:bcc, registrations |> Enum.map(& &1.email) |> Enum.uniq() |> Enum.join(","))

    ~H"""
    <details
      id={"course-#{@course.id}"}
      phx-mounted={JS.ignore_attributes(["open"])}
      class="bg-base-100 border-base-content/12 group border"
    >
      <summary class="cursor-pointer list-none p-4 sm:p-5">
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
          <a
            :if={@registrations != []}
            href={fastmail_compose(bcc: @bcc)}
            target="_blank"
            rel="noopener"
            class="btn btn-sm"
          >
            <.icon name="hero-envelope" class="h-4 w-4" />
            {~t"Email everyone"}
          </a>
          <button
            :if={is_nil(@booking_form)}
            type="button"
            phx-click="new_booking"
            phx-value-course-id={@course.id}
            class="btn btn-sm"
          >
            <.icon name="hero-plus" class="h-4 w-4" />
            {~t"Add booking"}
          </button>
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
            <button type="submit" class="btn btn-primary btn-sm">{~t"Add booking"}</button>
            <button type="button" phx-click="close_booking" class="btn btn-ghost btn-sm">{~t"Close"}</button>
          </div>
        </.form>

        <ul class="divide-base-content/12 divide-y">
          <li :for={registration <- @registrations} class="flex items-center justify-between gap-3 py-2.5">
            <div class="min-w-0">
              <p class="text-base-content truncate font-medium">
                {registration.name}
                <span :if={registration.seats_held > 1} class="text-base-content/65 tabular-nums">
                  +{registration.seats_held - 1}
                </span>
                <span
                  :if={registration.pays_at_course?}
                  class="badge badge-sm admin-badge-warning ml-1 align-middle"
                >
                  {~t"Pays at course"}
                </span>
              </p>
              <a
                href={fastmail_compose(to: registration.email)}
                target="_blank"
                rel="noopener"
                class="text-base-content/65 truncate text-sm hover:underline"
              >
                {registration.email}
              </a>
            </div>
            <div class="flex shrink-0 gap-1">
              <a
                :if={registration.payment_intent_id}
                href={StripeAPI.dashboard_payment_url(registration.payment_intent_id)}
                target="_blank"
                rel="noopener"
                class="btn btn-ghost btn-sm"
              >
                Stripe <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
              </a>
              <button
                :if={registration.seats_held > 1}
                type="button"
                phx-click="remove_seat"
                phx-value-id={registration.id}
                data-confirm={remove_seat_confirmation(registration)}
                class="btn btn-ghost btn-sm"
              >
                {~t"Remove a seat"}
              </button>
              <button
                :if={registration.pays_at_course?}
                type="button"
                phx-click="mark_paid"
                phx-value-id={registration.id}
                class="btn btn-sm"
              >
                {~t"Mark paid"}
              </button>
              <button
                type="button"
                phx-click="cancel"
                phx-value-id={registration.id}
                data-confirm={cancel_confirmation(registration)}
                class="btn btn-ghost btn-sm text-error"
              >
                {~t"Cancel"}
              </button>
            </div>
          </li>
          <li :for={registration <- @cancelled} class="text-base-content/50 py-2.5">
            <p class="truncate line-through">
              {registration.name}
              <span :if={registration.seats_held > 1} class="tabular-nums">+{registration.seats_held - 1}</span>
            </p>
            <p class="truncate text-sm">{registration.email}</p>
          </li>
        </ul>
      </div>
    </details>
    """
  end

  # Manual bookings never reach Stripe, so they have no payment intent.
  defp manual?(registration), do: is_nil(registration.payment_intent_id)

  defp remove_seat_confirmation(registration) do
    if manual?(registration) do
      ~t"Remove one seat from this booking?"
    else
      ~t"This does not refund. Refund one seat in Stripe first. Remove one seat from this booking?"
    end
  end

  defp cancel_confirmation(registration) do
    if manual?(registration) do
      ~t"This frees the seats. Refund them yourself if they paid. Cancel this booking?"
    else
      ~t"This frees the seats but does not refund. Refund in Stripe first. Cancel this booking?"
    end
  end

  # Jennie uses Fastmail on the web, so compose there rather than via mailto:.
  defp fastmail_compose(params), do: "https://app.fastmail.com/mail/compose?" <> URI.encode_query(params)
end

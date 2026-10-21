defmodule EdenflowersWeb.Admin.CoursesLive do
  use EdenflowersWeb, :live_view

  require Logger

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Format
  alias EdenflowersWeb.Admin.OrderLog
  alias EdenflowersWeb.Admin.PaymentActions
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: EdenflowersWeb.Endpoint.subscribe("admin:bookings")

    {:ok,
     socket
     |> assign(:page_title, ~t"Courses")
     |> assign(:locale, Localize.get_locale())
     |> assign(booking_form: nil, booking_course_id: nil, goodwill_params: %{})
     |> assign(settling_id: nil, settlement_mode: :settle, settlement_error: nil)
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
            <.button href={~q"/#{language}/courses"} target="_blank" variant="secondary" size="sm">
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> {~t"View in store"}
            </.button>
            <.button navigate={~p"/admin/courses/new"} variant="primary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" />
              {~t"New course"}
            </.button>
          </:actions>
        </.admin_page_header>

        <p :if={@courses == []} class="admin-card text-base-content/75 px-4 py-8 text-center text-sm sm:px-5">
          {~t"No upcoming courses"}
        </p>

        <div class="space-y-6">
          <.course
            :for={course <- @courses}
            course={course}
            locale={@locale}
            highlighted_booking_id={@highlighted_booking_id}
            goodwill_params={@goodwill_params}
          />
        </div>
      </.admin_page>
      <.booking_drawer
        form={@booking_form}
        course={Enum.find(@courses, &(&1.id == @booking_course_id))}
        locale={@locale}
      />
      <.settlement_drawer
        settling={find_booking(@courses, @settling_id)}
        mode={@settlement_mode}
        goodwill_params={@goodwill_params}
        error={@settlement_error}
        locale={@locale}
      />
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("new_booking", %{"course-id" => course_id}, socket) do
    form =
      AshPhoenix.Form.for_create(CourseRegistration, :add_manually,
        actor: socket.assigns.current_user,
        params: %{"payment_link?" => "true", "email_customer?" => "true"},
        transform_params: fn _form, params, _action -> Map.put(params, "course_id", course_id) end
      )
      |> to_form()

    {:noreply,
     socket
     |> assign(booking_form: form, booking_course_id: course_id)
     |> push_event("js-exec", %{to: "#booking-drawer", attr: "phx-show"})}
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
         |> push_event("js-exec", %{to: "#booking-drawer", attr: "phx-hide"})
         |> load_courses()}

      {:error, form} ->
        {:noreply, assign(socket, :booking_form, form)}
    end
  end

  def handle_event("open_settlement", %{"id" => id} = params, socket) do
    mode = if params["mode"] == "goodwill", do: :goodwill, else: :settle

    {:noreply,
     socket
     |> assign(settling_id: id, settlement_mode: mode, settlement_error: nil)
     |> push_event("js-exec", %{to: "#settlement-drawer", attr: "phx-show"})}
  end

  def handle_event("mark_paid", %{"registration_id" => id} = params, socket) do
    actor = socket.assigns.current_user

    settle(socket, id, fn registration ->
      params = Map.put(params, "amount", Decimal.to_string(registration.balance, :normal))
      PaymentActions.record_payment(registration, params, actor)
    end)
  end

  def handle_event("undo_payment", %{"id" => id, "payment-id" => payment_id}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &PaymentActions.undo_payment(&1, payment_id, actor))
  end

  def handle_event("refund", %{"record_id" => id, "refund" => params}, socket) do
    actor = socket.assigns.current_user
    settle(socket, id, &refund(&1, params, actor))
  end

  def handle_event("change_goodwill_refund", %{"record_id" => id, "goodwill_refund" => params}, socket) do
    {:noreply, update(socket, :goodwill_params, &Map.put(&1, id, params))}
  end

  def handle_event("goodwill_refund", %{"record_id" => id, "goodwill_refund" => params}, socket) do
    actor = socket.assigns.current_user
    settle(socket, id, &PaymentActions.goodwill_refund(&1, params, actor))
  end

  def handle_event("open_payment_link", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &PaymentActions.open_payment_link(&1, actor))
  end

  def handle_event("email_payment_link", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &PaymentActions.email_payment_link(&1, actor))
  end

  def handle_event("email_confirmation", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &email_confirmation(&1, actor))
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

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "admin:bookings"}, socket), do: {:noreply, load_courses(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp with_registration(socket, id, payment_action) do
    socket =
      case Courses.get_registration_by_id(id, actor: socket.assigns.current_user) do
        {:ok, registration} ->
          {kind, message} = payment_action.(registration)
          put_flash(socket, kind, message)

        {:error, _error} ->
          put_flash(socket, :error, ~t"Booking not found.")
      end

    {:noreply, load_courses(socket)}
  end

  # The drawer closes once the money is recorded. On an error it stays open, and the
  # form keeps what Jennie entered because the server never re-renders those inputs.
  defp settle(socket, id, payment_action) do
    socket =
      case Courses.get_registration_by_id(id, actor: socket.assigns.current_user, load: [:balance]) do
        {:ok, registration} ->
          case payment_action.(registration) do
            {:info, message} ->
              socket
              |> put_flash(:info, message)
              |> assign(settling_id: nil, settlement_error: nil)
              |> update(:goodwill_params, &Map.delete(&1, id))
              |> push_event("js-exec", %{to: "#settlement-drawer", attr: "phx-hide"})

            {:error, message} ->
              assign(socket, :settlement_error, message)
          end

        {:error, _error} ->
          assign(socket, :settlement_error, ~t"Booking not found.")
      end

    {:noreply, load_courses(socket)}
  end

  defp find_booking(_courses, nil), do: nil

  defp find_booking(courses, id) do
    Enum.find_value(courses, fn course ->
      booking = Enum.find(course.bookings, &(&1.id == id))
      booking && {course, booking}
    end)
  end

  defp email_confirmation(registration, actor) do
    case Courses.email_registration_confirmation(registration, actor: actor) do
      {:ok, _registration} ->
        {:info, ~t"Confirmation emailed."}

      {:error, error} ->
        Logger.error("Confirmation for course registration #{registration.id} not emailed: #{inspect(error)}")
        {:error, ~t"Could not email the confirmation."}
    end
  end

  # The amount Jennie leaves in the form is what's handed back; the rest of the balance is kept.
  defp refund(registration, %{"amount" => amount} = params, actor) do
    amount = String.replace(amount, ",", ".")

    case Courses.set_registration_refund(registration, amount, actor: actor, load: [:outside_stripe_refund]) do
      {:ok, registration} -> refund_by(registration, params, actor)
      {:error, error} -> {:error, PaymentActions.payment_error(error)}
    end
  end

  defp refund_by(registration, %{"by" => "stripe"}, _actor), do: PaymentActions.refund_with_stripe(registration)

  defp refund_by(registration, %{"payment_method" => payment_method}, actor) do
    amount = registration.outside_stripe_refund |> Decimal.negate() |> Decimal.to_string(:normal)
    PaymentActions.record_payment(registration, %{"amount" => amount, "payment_method" => payment_method}, actor)
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
            :paid_outside_stripe,
            :paid_through_stripe,
            :goodwill_refundable?,
            :seats_held,
            :payment_link_open?,
            payments: [:undoable?, :reversal]
          ]
        ]
      )

    assign(socket, :courses, courses)
  end

  attr :course, :map, required: true
  attr :locale, :any, required: true
  attr :highlighted_booking_id, :string, default: nil
  attr :goodwill_params, :map, required: true, doc: "each booking's refund form as filled in so far, by its id"

  defp course(assigns) do
    {registrations, cancelled} = Enum.split_with(assigns.course.bookings, &(&1.status == :confirmed))

    assigns =
      assigns
      |> assign(:cancelled_to_refund, Enum.filter(cancelled, &to_refund?/1))
      |> assign(:cancelled_settled, Enum.reject(cancelled, &to_refund?/1))
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
      class="admin-card group/course"
    >
      <summary class="cursor-pointer list-none p-4 hover:bg-base-300/40 focus-visible:outline-offset-[-2px] focus-visible:outline-primary focus-visible:outline-2 sm:p-5">
        <div class="flex items-start gap-3">
          <div class="min-w-0 flex-1">
            <h2 class="text-base-content text-base font-semibold">
              {@course.name}
              <.badge :if={@past?} tone={:tag} class="ml-1 align-middle">{pgettext("course", "Past")}</.badge>
            </h2>
            <p class="text-base-content/75 mt-0.5 text-sm tabular-nums">
              {Format.date(@course.date, @locale)}, {Format.time(@course.start_time, @locale)}–{Format.time(
                @course.end_time,
                @locale
              )}
            </p>
          </div>
          <div class="text-base-content/75 hidden shrink-0 items-center gap-4 text-sm tabular-nums lg:flex">
            <span class="whitespace-nowrap">{~t"#{@seats} / #{total = @course.total_places} seats"}</span>
            <span :if={@still_to_pay > 0} class="whitespace-nowrap">{~t"#{count = @still_to_pay} to collect"}</span>
          </div>
          <.icon
            name="hero-chevron-down"
            class="text-base-content/50 h-4 w-4 shrink-0 transition-transform group-open/course:rotate-180"
          />
        </div>
        <div class="text-base-content/75 mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm tabular-nums lg:hidden">
          <span class="whitespace-nowrap">{~t"#{@seats} / #{total = @course.total_places} seats"}</span>
          <span :if={@still_to_pay > 0} class="whitespace-nowrap">
            {~t"#{count = @still_to_pay} to collect"}
          </span>
        </div>
      </summary>

      <div class="border-base-content/12 border-t p-4 sm:p-5">
        <p :if={@registrations == []} class="text-base-content/75 mb-4 text-sm">{~t"No bookings yet"}</p>
        <div class="mb-5 flex flex-wrap items-center gap-2">
          <.button
            type="button"
            phx-click="new_booking"
            phx-value-course-id={@course.id}
            variant="secondary"
            size="sm"
          >
            <.icon name="hero-plus" class="h-4 w-4" />
            {~t"Add booking"}
          </.button>
          <.button
            :if={@registrations != []}
            href={fastmail_compose(bcc: @bcc)}
            target="_blank"
            rel="noopener"
            variant="secondary"
            size="sm"
          >
            <.icon name="hero-envelope" class="h-4 w-4" />
            {~t"Email everyone"}
          </.button>
          <.button navigate={~p"/admin/courses/#{@course.id}"} variant="secondary" size="sm">
            <.icon name="hero-pencil-square" class="h-4 w-4" />
            {~t"Edit course"}
          </.button>
        </div>

        <ul class="divide-base-content/12 grid-cols-[minmax(0,1fr)_2rem] grid gap-x-3 divide-y">
          <li
            :for={registration <- @registrations}
            id={"registration-#{registration.id}"}
            aria-current={registration.id == @highlighted_booking_id && "true"}
            class={["grid-cols-subgrid col-span-full grid items-center gap-y-3 py-4", registration.id == @highlighted_booking_id && highlighted_row_class()]}
          >
            <div class="contents">
              <div class="col-start-1 row-start-1 min-w-0">
                <p class="text-base-content flex flex-wrap items-center gap-x-2 gap-y-1 font-medium">
                  <span class="min-w-0 break-words">{registration.name}</span>
                  <span :if={registration.seats_held > 1} class="text-base-content/75 tabular-nums">
                    +{registration.seats_held - 1}
                  </span>
                  <.settlement_badge registration={registration} locale={@locale} />
                </p>
                <a
                  href={fastmail_compose(to: registration.email)}
                  target="_blank"
                  rel="noopener"
                  class="text-base-content/75 block w-fit truncate text-sm pointer-coarse:py-3 hover:underline"
                >
                  {registration.email}
                </a>
                <.goodwill_refunds registration={registration} locale={@locale} />
              </div>
              <div class="col-start-2 row-start-1 justify-self-end">
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
                    menu={"registration-actions-#{registration.id}"}
                    phx-click="email_confirmation"
                    phx-value-id={registration.id}
                    data-confirm={email_confirmation_confirmation(registration, @locale)}
                  >
                    {if registration.confirmation_emailed_at,
                      do: ~t"Resend confirmation",
                      else: ~t"Email confirmation"}
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
                    {~t"Get payment link"}
                  </.actions_menu_button>
                  <.actions_menu_button
                    :if={registration.goodwill_refundable?}
                    menu={"registration-actions-#{registration.id}"}
                    phx-click="open_settlement"
                    phx-value-id={registration.id}
                    phx-value-mode="goodwill"
                  >
                    {~t"Refund"}
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
          </li>
          <.cancelled_row
            :for={registration <- @cancelled_to_refund}
            registration={registration}
            highlighted_booking_id={@highlighted_booking_id}
            locale={@locale}
          />
        </ul>

        <details
          :if={@cancelled_settled != []}
          id={"cancelled-#{@course.id}"}
          open={Enum.any?(@cancelled_settled, &(&1.id == @highlighted_booking_id))}
          phx-mounted={JS.ignore_attributes(["open"])}
          class="group/cancelled border-base-content/12 border-t"
        >
          <summary class="text-base-content/75 touch-target flex cursor-pointer list-none items-center gap-1 py-3 text-sm">
            {~t"Cancelled (#{count = length(@cancelled_settled)})"}
            <.icon name="hero-chevron-down" class="h-4 w-4 group-open/cancelled:rotate-180" />
          </summary>
          <ul class="divide-base-content/12 grid-cols-[minmax(0,1fr)_2rem] grid gap-x-3 divide-y">
            <.cancelled_row
              :for={registration <- @cancelled_settled}
              registration={registration}
              highlighted_booking_id={@highlighted_booking_id}
              locale={@locale}
            />
          </ul>
        </details>
      </div>
    </details>
    """
  end

  attr :registration, :map, required: true
  attr :highlighted_booking_id, :string, required: true
  attr :locale, :any, required: true

  defp cancelled_row(assigns) do
    ~H"""
    <li
      id={"registration-#{@registration.id}"}
      data-status="cancelled"
      aria-current={@registration.id == @highlighted_booking_id && "true"}
      class={["grid-cols-subgrid col-span-full grid items-center gap-y-3 py-4", @registration.id == @highlighted_booking_id && highlighted_row_class()]}
    >
      <div class="col-start-1 row-start-1 min-w-0">
        <p class="text-base-content/75 flex flex-wrap items-center gap-x-2 gap-y-1">
          <span class="line-through">
            {@registration.name}
            <span :if={@registration.seats_held > 1} class="tabular-nums">+{@registration.seats_held - 1}</span>
          </span>
          <.settlement_badge registration={@registration} locale={@locale} />
        </p>
        <p class="text-base-content/75 truncate text-sm">{@registration.email}</p>
      </div>
    </li>
    """
  end

  defp payment_options do
    [%{name: ~t"Send a payment link", value: "true"}, %{name: ~t"Record the payment later", value: "false"}]
  end

  # A paid booking's PaymentIntent is on its Payment; a pending one's is still on the booking.
  defp stripe_payment_intent_id(registration),
    do: Enum.find_value(registration.payments, & &1.payment_intent_id) || registration.payment_intent_id

  defp to_collect?(registration), do: not registration.settled? and Decimal.positive?(registration.balance)

  defp to_refund?(registration), do: not registration.settled? and Decimal.negative?(registration.balance)

  attr :registration, :map, required: true
  attr :locale, :string, required: true

  # Opens the settlement drawer, so the amount owed doubles as the way to settle it.
  defp settlement_badge(assigns) do
    ~H"""
    <.badge
      :if={to_collect?(@registration) or to_refund?(@registration)}
      id={"settle-#{@registration.id}"}
      type="button"
      tone={if to_collect?(@registration), do: :warning, else: :error}
      class="tabular-nums"
      aria-haspopup="dialog"
      aria-controls="settlement-drawer"
      phx-click="open_settlement"
      phx-value-id={@registration.id}
    >
      {if to_collect?(@registration),
        do: ~t"To collect #{amount = Format.currency(@registration.balance, @locale)}",
        else: ~t"To refund #{amount = Format.currency(Decimal.abs(@registration.balance), @locale)}"}
      <.icon name="hero-chevron-right" class="-mr-0.5 h-3.5 w-3.5 shrink-0" />
    </.badge>
    """
  end

  attr :registration, :map, required: true
  attr :locale, :string, required: true

  defp goodwill_refunds(assigns) do
    assigns =
      assign(
        assigns,
        :refunds,
        Enum.filter(
          assigns.registration.payments,
          &(&1.goodwill and Decimal.negative?(&1.amount) and is_nil(&1.reversal))
        )
      )

    ~H"""
    <p :for={refund <- @refunds} class="text-base-content/75 text-sm">
      {~t"Goodwill refund #{amount = Format.currency(Decimal.abs(refund.amount), @locale)} · #{how = OrderLog.payment_method_label(refund.method)}"}
      <span :if={refund.note}>· {refund.note}</span>
    </p>
    """
  end

  attr :form, :any, required: true
  attr :course, :map, required: true
  attr :locale, :string, required: true

  defp booking_drawer(assigns) do
    ~H"""
    <.admin_drawer id="booking-drawer" title={~t"Add booking"} on_close={JS.push("close_booking")}>
      <.form
        :if={@form && @course}
        for={@form}
        id={"booking-form-#{@course.id}"}
        phx-change="validate_booking"
        phx-submit="save_booking"
        class="flex min-h-0 flex-1 flex-col"
      >
        <.drawer_body>
          <p class="text-base-content/75 text-sm">
            {@course.name} · {Format.date(@course.date, @locale)}, {Format.time(@course.start_time, @locale)}
          </p>
          <div class="space-y-4">
            <.input field={@form[:name]} type="text" label={~t"Name"} class="input w-full" />
            <.input field={@form[:email]} type="email" label={~t"Email"} class="input w-full" />
            <div class="grid grid-cols-2 gap-x-3 gap-y-4">
              <.input
                field={@form[:seats]}
                type="number"
                label={~t"Seats"}
                min="1"
                max={CourseRegistration.max_seats()}
                class="input w-full"
              />
              <.input
                field={@form[:locale]}
                type="select"
                label={~t"Language"}
                options={[{"Svenska", "sv-FI"}, {"Suomi", "fi"}, {"English", "en-GB"}]}
                class="select w-full"
              />
            </div>
            <.input :let={option} field={@form[:payment_link?]} type="radio-card" options={payment_options()}>
              {option.name}
            </.input>
            <.input
              field={@form[:email_customer?]}
              type="checkbox"
              label={~t"Email the booking confirmation to the customer"}
            />
          </div>
        </.drawer_body>
        <.drawer_footer>
          <.button type="submit" variant="primary" phx-disable-with={~t"Adding…"}>{~t"Add booking"}</.button>
          <.button
            type="button"
            phx-click={JS.exec("phx-hide", to: "#booking-drawer") |> JS.push("close_booking")}
            variant="ghost"
          >
            {~t"Cancel"}
          </.button>
        </.drawer_footer>
      </.form>
    </.admin_drawer>
    """
  end

  attr :settling, :any, required: true, doc: "the {course, booking} being settled, or nil"
  attr :mode, :atom, required: true, values: [:settle, :goodwill]
  attr :goodwill_params, :map, required: true
  attr :error, :string, default: nil
  attr :locale, :string, required: true

  defp settlement_drawer(assigns) do
    ~H"""
    <.admin_drawer id="settlement-drawer" title={settlement_title(@settling, @mode)}>
      <.drawer_body :if={@settling}>
        <.settlement_details course={elem(@settling, 0)} registration={elem(@settling, 1)} locale={@locale} />
        <p :if={@error} role="alert" class="text-error text-sm">{@error}</p>
        <.goodwill_refund_form
          :if={@mode == :goodwill and elem(@settling, 1).goodwill_refundable?}
          id={"goodwill-refund-#{elem(@settling, 1).id}"}
          record={elem(@settling, 1)}
          locale={@locale}
          params={Map.get(@goodwill_params, elem(@settling, 1).id, %{})}
          hidden={false}
        />
        <.mark_paid_form :if={@mode == :settle and to_collect?(elem(@settling, 1))} registration={elem(@settling, 1)} />
        <.refund_controls :if={@mode == :settle and to_refund?(elem(@settling, 1))} registration={elem(@settling, 1)} />
        <p :if={nothing_to_settle?(elem(@settling, 1), @mode)} class="text-base-content/75 text-sm">
          {~t"Nothing left to settle on this booking."}
        </p>
      </.drawer_body>
    </.admin_drawer>
    """
  end

  defp settlement_title(_settling, :goodwill), do: ~t"Refund"

  defp settlement_title({_course, registration}, :settle) do
    if to_refund?(registration), do: ~t"Record refund", else: ~t"Record payment"
  end

  defp settlement_title(nil, :settle), do: ~t"Record payment"

  defp nothing_to_settle?(registration, :goodwill), do: not registration.goodwill_refundable?
  defp nothing_to_settle?(registration, :settle), do: not to_collect?(registration) and not to_refund?(registration)

  attr :course, :map, required: true
  attr :registration, :map, required: true
  attr :locale, :string, required: true

  defp settlement_details(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-base-content font-medium">
        {@registration.name}
        <span :if={@registration.seats_held > 1} class="text-base-content/75 tabular-nums">
          +{@registration.seats_held - 1}
        </span>
        <.badge :if={@registration.status == :cancelled} tone={:tag} class="ml-1 align-middle">
          {~t"Cancelled"}
        </.badge>
      </p>
      <p class="text-base-content/75 break-all text-sm">{@registration.email}</p>
      <p class="text-base-content/75 text-sm">
        {@course.name} · {Format.date(@course.date, @locale)}, {Format.time(@course.start_time, @locale)}
      </p>
    </div>
    <dl class="divide-base-content/12 border-base-content/12 divide-y border-y text-sm tabular-nums">
      <div class="flex justify-between gap-4 py-2">
        <dt class="text-base-content/75">{~t"Paid"}</dt>
        <dd>{Format.currency(@registration.amount_paid, @locale)}</dd>
      </div>
      <div :if={to_collect?(@registration)} class="flex justify-between gap-4 py-2">
        <dt class="text-base-content/75">{~t"To collect"}</dt>
        <dd class="font-semibold">{Format.currency(@registration.balance, @locale)}</dd>
      </div>
      <div
        :if={@registration.status == :cancelled and Decimal.positive?(@registration.kept_amount)}
        class="flex justify-between gap-4 py-2"
      >
        <dt class="text-base-content/75">{~t"Kept as cancellation fee"}</dt>
        <dd>{Format.currency(@registration.kept_amount, @locale)}</dd>
      </div>
      <div :if={to_refund?(@registration)} class="flex justify-between gap-4 py-2">
        <dt class="text-base-content/75">{~t"To refund"}</dt>
        <dd class="font-semibold">{Format.currency(Decimal.abs(@registration.balance), @locale)}</dd>
      </div>
    </dl>
    """
  end

  attr :registration, :map, required: true

  defp mark_paid_form(assigns) do
    ~H"""
    <form id={"mark-paid-#{@registration.id}"} phx-submit="mark_paid" class="space-y-4">
      <input type="hidden" name="registration_id" value={@registration.id} />
      <.input
        id={"mark-paid-method-#{@registration.id}"}
        name="payment_method"
        type="select"
        label={~t"Payment method"}
        value={:zettle}
        options={payment_method_options()}
        class="select w-full"
      />
      <.input name="email_receipt" type="checkbox" label={~t"Email a receipt"} value="true" />
      <.button type="submit" variant="primary" phx-disable-with={~t"Recording…"}>{~t"Record payment"}</.button>
    </form>
    """
  end

  attr :registration, :map, required: true

  # Money taken by card goes back through Stripe; cash or Zettle money is recorded as handed back.
  # The amount starts at the balance, which leaves out a late-cancellation fee, and Jennie can change it.
  defp refund_controls(assigns) do
    ~H"""
    <form id={"refund-#{@registration.id}"} phx-submit="refund" class="space-y-4">
      <input type="hidden" name="record_id" value={@registration.id} />
      <.input
        id={"refund-amount-#{@registration.id}"}
        name="refund[amount]"
        type="text"
        inputmode="decimal"
        label={~t"Amount to refund (€)"}
        value={Decimal.to_string(Decimal.abs(@registration.balance), :normal)}
        class="input w-full tabular-nums"
      />
      <div :if={Decimal.positive?(@registration.stripe_refund)} class="space-y-4">
        <p class="text-base-content/75 text-sm">
          {~t"Sends the money back to the customer's card. Stripe moves the money."}
        </p>
        <.button
          name="refund[by]"
          value="stripe"
          type="submit"
          phx-disable-with={~t"Refunding…"}
          data-confirm={~t"Refund this amount to the customer's card with Stripe?"}
          variant="primary"
        >
          {~t"Refund with Stripe"}
        </.button>
      </div>
      <div :if={Decimal.positive?(@registration.outside_stripe_refund)} class="space-y-4">
        <p class="text-base-content/75 text-sm">
          {~t"Records money you have already handed back. Nothing is sent to the customer."}
        </p>
        <.input
          id={"refund-method-#{@registration.id}"}
          name="refund[payment_method]"
          type="select"
          label={~t"Payment method"}
          value={:zettle}
          options={payment_method_options()}
          class="select w-full"
        />
        <.button
          name="refund[by]"
          value="record"
          type="submit"
          phx-disable-with={~t"Recording…"}
          variant="primary"
          data-confirm={~t"Record this amount as refunded? A mistake can be undone afterwards."}
        >
          {~t"Record refund"}
        </.button>
      </div>
    </form>
    """
  end

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

  defp email_confirmation_confirmation(registration, locale) do
    question = ~t"Email the booking confirmation to #{email = registration.email}?"

    if registration.confirmation_emailed_at,
      do: ~t"Last sent #{time = Format.datetime(registration.confirmation_emailed_at, locale)}." <> " " <> question,
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

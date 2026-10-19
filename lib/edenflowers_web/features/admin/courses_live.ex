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
    {:ok,
     socket
     |> assign(:page_title, ~t"Courses")
     |> assign(:locale, Localize.get_locale())
     |> assign(booking_form: nil, booking_course_id: nil, goodwill_params: %{})
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
            <.button href={~p"/courses"} target="_blank" variant="ghost" size="sm">
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> {~t"View in store"}
            </.button>
            <.button navigate={~p"/admin/courses/new"} variant="neutral" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" />
              {~t"New course"}
            </.button>
          </:actions>
        </.admin_page_header>

        <p :if={@courses == []} class="text-base-content/65 py-6 text-center text-sm">
          {~t"No upcoming courses"}
        </p>

        <div class="space-y-6">
          <.course
            :for={course <- @courses}
            course={course}
            locale={@locale}
            booking_form={if @booking_course_id == course.id, do: @booking_form}
            highlighted_booking_id={@highlighted_booking_id}
            goodwill_params={@goodwill_params}
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
        params: %{"payment_link?" => "true", "email_customer?" => "true"},
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
  def handle_event("mark_paid", %{"registration_id" => id} = params, socket) do
    actor = socket.assigns.current_user

    socket =
      case Courses.get_registration_by_id(id, actor: actor, load: [:balance]) do
        {:ok, registration} ->
          params = Map.put(params, "amount", Decimal.to_string(registration.balance, :normal))
          {kind, message} = PaymentActions.record_payment(registration, params, actor)
          put_flash(socket, kind, message)

        {:error, _error} ->
          put_flash(socket, :error, ~t"Booking not found.")
      end

    {:noreply, load_courses(socket)}
  end

  def handle_event("undo_payment", %{"id" => id, "payment-id" => payment_id}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &PaymentActions.undo_payment(&1, payment_id, actor))
  end

  def handle_event("refund", %{"record_id" => id, "refund" => params}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &refund(&1, params, actor))
  end

  def handle_event("change_goodwill_refund", %{"record_id" => id, "goodwill_refund" => params}, socket) do
    {:noreply, update(socket, :goodwill_params, &Map.put(&1, id, params))}
  end

  def handle_event("goodwill_refund", %{"record_id" => id, "goodwill_refund" => params}, socket) do
    actor = socket.assigns.current_user
    socket = update(socket, :goodwill_params, &Map.delete(&1, id))
    with_registration(socket, id, &PaymentActions.goodwill_refund(&1, params, actor))
  end

  def handle_event("open_payment_link", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &PaymentActions.open_payment_link(&1, actor))
  end

  def handle_event("email_payment_link", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &PaymentActions.email_payment_link(&1, actor))
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
  attr :booking_form, :any, required: true
  attr :highlighted_booking_id, :string, default: nil
  attr :goodwill_params, :map, required: true, doc: "each booking's refund form as filled in so far, by its id"

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
      class="group/course border-base-content/12 border-y"
    >
      <summary class="list-none p-4 sm:p-5">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h2 class="text-base-content font-semibold">
              {@course.name}
              <.badge :if={@past?} tone={:tag} class="ml-1 align-middle">{pgettext("course", "Past")}</.badge>
            </h2>
            <p class="text-base-content/65 text-sm">
              {Format.date(@course.date, @locale)}, {Format.time(@course.start_time, @locale)}–{Format.time(
                @course.end_time,
                @locale
              )}
            </p>
          </div>
          <.icon
            name="hero-chevron-down"
            class="text-base-content/50 h-5 w-5 shrink-0 group-open/course:rotate-180"
          />
        </div>
        <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm tabular-nums">
          <span class="whitespace-nowrap">{~t"#{@seats} / #{total = @course.total_places} seats"}</span>
          <progress
            class="progress progress-primary h-1 w-24"
            value={@seats}
            max={@course.total_places}
            aria-label={~t"Seats"}
          />
          <span :if={@still_to_pay > 0} class="text-base-content/65">
            {~t"#{count = @still_to_pay} to collect"}
          </span>
        </div>
      </summary>

      <div class="border-base-content/12 border-t p-4 sm:p-5">
        <p :if={@registrations == []} class="text-base-content/65 mb-4 text-sm">{~t"No bookings yet"}</p>
        <div class="mb-5 flex flex-wrap items-center gap-2">
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
          <.button
            :if={@registrations != []}
            href={fastmail_compose(bcc: @bcc)}
            target="_blank"
            rel="noopener"
            variant="ghost"
            size="sm"
          >
            <.icon name="hero-envelope" class="h-4 w-4" />
            {~t"Email everyone"}
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
              class="select w-full"
            />
          </div>
          <.input
            :let={option}
            field={@booking_form[:payment_link?]}
            type="radio-card"
            options={payment_options()}
          >
            {option.name}
          </.input>
          <.input
            field={@booking_form[:email_customer?]}
            type="checkbox"
            label={~t"Email the booking confirmation to the customer"}
          />
          <div class="flex gap-2">
            <.button type="submit" variant="primary">{~t"Add booking"}</.button>
            <.button type="button" phx-click="close_booking" variant="ghost">{~t"Close"}</.button>
          </div>
        </.form>

        <ul class="divide-base-content/8 grid-cols-[minmax(0,1fr)_2rem] grid gap-x-3 divide-y sm:grid-cols-[minmax(0,1fr)_auto_2rem]">
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
                  <span :if={registration.seats_held > 1} class="text-base-content/65 tabular-nums">
                    +{registration.seats_held - 1}
                  </span>
                  <.badge :if={to_collect?(registration)} tone={:warning}>
                    {~t"To collect"}
                  </.badge>
                  <.to_refund_badge registration={registration} locale={@locale} />
                </p>
                <a
                  href={fastmail_compose(to: registration.email)}
                  target="_blank"
                  rel="noopener"
                  class="text-base-content/65 block truncate text-sm pointer-coarse:py-3 hover:underline"
                >
                  {registration.email}
                </a>
                <.goodwill_refunds registration={registration} locale={@locale} />
              </div>
              <.settlement_button registration={registration} />
              <div class="col-start-2 row-start-1 justify-self-end sm:col-start-3">
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
                    :if={registration.goodwill_refundable?}
                    menu={"registration-actions-#{registration.id}"}
                    phx-click={
                      JS.show(to: "#goodwill-refund-#{registration.id}")
                      |> JS.focus(to: "#goodwill-refund-#{registration.id}-amount")
                    }
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
            <.settlement_panel registration={registration} />
            <.goodwill_refund_form
              :if={registration.goodwill_refundable?}
              id={"goodwill-refund-#{registration.id}"}
              record={registration}
              locale={@locale}
              params={Map.get(@goodwill_params, registration.id, %{})}
              class="bg-base-200/50 col-span-full row-start-4 min-w-0 p-4 sm:row-start-3"
            />
          </li>
          <li
            :for={registration <- @cancelled}
            id={"registration-#{registration.id}"}
            data-status="cancelled"
            aria-current={registration.id == @highlighted_booking_id && "true"}
            class={["grid-cols-subgrid col-span-full grid items-center gap-y-3 py-4", registration.id == @highlighted_booking_id && highlighted_row_class()]}
          >
            <div class="col-start-1 row-start-1 min-w-0">
              <p class="text-base-content/65 flex flex-wrap items-center gap-x-2 gap-y-1">
                <span class="line-through">
                  {registration.name}
                  <span :if={registration.seats_held > 1} class="tabular-nums">+{registration.seats_held - 1}</span>
                </span>
                <.to_refund_badge registration={registration} locale={@locale} />
              </p>
              <p class="text-base-content/65 truncate text-sm">{registration.email}</p>
            </div>
            <.settlement_button registration={registration} />
            <.settlement_panel registration={registration} />
          </li>
        </ul>
      </div>
    </details>
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

  defp to_refund_badge(assigns) do
    ~H"""
    <.badge
      :if={to_refund?(@registration)}
      tone={:error}
      class="tabular-nums"
    >
      {~t"To refund #{amount = Format.currency(Decimal.abs(@registration.balance), @locale)}"}
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
    <p :for={refund <- @refunds} class="text-base-content/65 text-sm">
      {~t"Goodwill refund #{amount = Format.currency(Decimal.abs(refund.amount), @locale)} · #{how = OrderLog.payment_method_label(refund.method)}"}
      <span :if={refund.note}>· {refund.note}</span>
    </p>
    """
  end

  attr :registration, :map, required: true

  defp settlement_button(assigns) do
    ~H"""
    <.button
      :if={to_collect?(@registration) or to_refund?(@registration)}
      id={"settlement-toggle-#{@registration.id}"}
      type="button"
      variant="ghost"
      size="sm"
      class="col-start-1 row-start-2 justify-self-start sm:col-start-2 sm:row-start-1"
      aria-expanded="false"
      aria-controls={"settlement-#{@registration.id}"}
      phx-click={
        JS.toggle(to: "#settlement-#{@registration.id}")
        |> JS.toggle_attribute({"aria-expanded", "true", "false"})
      }
    >
      {if to_collect?(@registration), do: ~t"Record payment", else: ~t"Record refund"}
      <.icon name="hero-chevron-down" class="h-4 w-4" />
    </.button>
    """
  end

  attr :registration, :map, required: true

  defp settlement_panel(assigns) do
    ~H"""
    <div
      :if={to_collect?(@registration) or to_refund?(@registration)}
      id={"settlement-#{@registration.id}"}
      role="region"
      aria-labelledby={"settlement-toggle-#{@registration.id}"}
      class="bg-base-200/50 col-span-full row-start-3 hidden min-w-0 p-4 sm:row-start-2"
    >
      <form
        :if={to_collect?(@registration)}
        id={"mark-paid-#{@registration.id}"}
        phx-submit="mark_paid"
        class="flex flex-wrap items-end gap-4"
      >
        <input type="hidden" name="registration_id" value={@registration.id} />
        <label class="flex w-full flex-col gap-1 text-sm sm:w-auto">
          {~t"Payment method"}
          <select id={"mark-paid-method-#{@registration.id}"} name="payment_method" class="select select-sm w-full sm:w-48">
            {Phoenix.HTML.Form.options_for_select(payment_method_options(), :zettle)}
          </select>
        </label>
        <label class="flex h-8 items-center gap-2 text-sm pointer-coarse:min-h-11">
          <input type="hidden" name="email_receipt" value="false" />
          <input type="checkbox" name="email_receipt" value="true" checked class="checkbox checkbox-sm" />
          {~t"Email a receipt"}
        </label>
        <.button type="submit" variant="primary" size="sm">{~t"Record payment"}</.button>
      </form>
      <.refund_controls :if={to_refund?(@registration)} registration={@registration} />
    </div>
    """
  end

  attr :registration, :map, required: true

  # Money taken by card goes back through Stripe; cash or Zettle money is recorded as handed back.
  # The amount starts at the balance, which leaves out a late-cancellation fee, and Jennie can change it.
  defp refund_controls(assigns) do
    ~H"""
    <form
      id={"refund-#{@registration.id}"}
      phx-submit="refund"
      class="flex flex-wrap items-end gap-4"
    >
      <input type="hidden" name="record_id" value={@registration.id} />
      <label class="flex w-full flex-col gap-1 text-sm sm:w-auto">
        {~t"Amount to refund (€)"}
        <input
          id={"refund-amount-#{@registration.id}"}
          name="refund[amount]"
          type="text"
          inputmode="decimal"
          value={Decimal.to_string(Decimal.abs(@registration.balance), :normal)}
          class="input input-sm w-full tabular-nums sm:w-40"
        />
      </label>
      <.button
        :if={Decimal.positive?(@registration.stripe_refund)}
        name="refund[by]"
        value="stripe"
        type="submit"
        phx-disable-with={~t"Refunding…"}
        data-confirm={~t"Refund this amount to the customer's card with Stripe?"}
        variant="neutral"
        size="sm"
      >
        {~t"Refund with Stripe"}
      </.button>
      <%= if Decimal.positive?(@registration.outside_stripe_refund) do %>
        <label class="flex w-full flex-col gap-1 text-sm sm:w-auto">
          {~t"Payment method"}
          <select
            id={"refund-method-#{@registration.id}"}
            name="refund[payment_method]"
            class="select select-sm w-full sm:w-48"
          >
            {Phoenix.HTML.Form.options_for_select(payment_method_options(), :zettle)}
          </select>
        </label>
        <.button
          name="refund[by]"
          value="record"
          type="submit"
          variant="neutral"
          size="sm"
          data-confirm={~t"Record this amount as refunded? A mistake can be undone afterwards."}
        >
          {~t"Record refund"}
        </.button>
      <% end %>
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

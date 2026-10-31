defmodule EdenflowersWeb.Admin.CourseDetailLive do
  @moduledoc """
  Admin course page for bookings, balances, refunds, and customer emails.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  require Logger

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.Drawers
  import EdenflowersWeb.Admin.CourseBookingDrawers

  alias Edenflowers.Courses
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Format
  alias Edenflowers.Translations
  alias EdenflowersWeb.Admin.DrawerPreview
  alias EdenflowersWeb.Admin.EmailDrawer
  alias EdenflowersWeb.Admin.OrderLog
  alias EdenflowersWeb.Admin.ShareLinkDrawer
  alias EdenflowersWeb.Admin.PaymentActions
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case load_course(socket, id) do
      {:ok, socket} ->
        if connected?(socket), do: EdenflowersWeb.Endpoint.subscribe("admin:bookings")

        {:ok,
         socket
         |> assign(:page_title, socket.assigns.course.name)
         |> assign(:locale, Localize.get_locale())
         |> assign(refund_params: %{}, payment_params: %{})
         |> assign(settling_id: nil, settlement_mode: :settle, settlement_error: nil)
         |> assign(cancelling: nil, cancel_form: nil, cancel_error: nil)
         |> assign(email_form: nil, email_kind: nil, emailing_id: nil, preview: nil)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Course not found.")
         |> push_navigate(to: ~p"/admin/courses")}
    end
  end

  # The Overview links here with ?booking= to point at that booking.
  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, assign(socket, :highlighted_booking_id, params["booking"])}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={@course.name} back={{~t"Courses", ~p"/admin/courses"}}>
          <:subtitle>
            <span class="inline-flex flex-wrap items-center gap-x-2 tabular-nums">
              <span>
                {Format.date(@course.date, @locale)}, {Format.time(@course.start_time, @locale)}–{Format.time(
                  @course.end_time,
                  @locale
                )}
              </span>
              <span aria-hidden="true">·</span>
              <span class="whitespace-nowrap">{~t"#{seats = @course.seats_booked} / #{total = @course.total_places} seats"}</span>
              <.badge :if={@past?} tone={:tag}>{dpgettext("admin", "course", "Past")}</.badge>
            </span>
          </:subtitle>
          <:actions>
            <.button
              :if={@registrations != []}
              href={fastmail_compose(bcc: @bcc)}
              data-app-href={fastmail_app_compose(bcc: @bcc)}
              target="_blank"
              rel="noopener"
              variant="secondary"
              size="sm"
            >
              <.icon name="hero-envelope" class="h-4 w-4" />
              {~t"Email everyone"}
            </.button>
            <ShareLinkDrawer.open_button :if={!@past?} id="share-course-link" />
            <.button navigate={~p"/admin/courses/#{@course.id}/edit"} variant="secondary" size="sm">
              <.icon name="hero-pencil-square" class="h-4 w-4" />
              {~t"Edit course"}
            </.button>
            <.button navigate={~p"/admin/courses/#{@course.id}/bookings/new"} variant="primary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" />
              {~t"Add booking"}
            </.button>
          </:actions>
        </.admin_page_header>

        <section id="bookings" class="admin-card p-4 sm:p-5">
          <p :if={@registrations == []} class="text-base-content/75 text-sm">{~t"No bookings yet"}</p>

          <ul class="divide-base-content/12 grid-cols-[minmax(0,1fr)_2rem] grid gap-x-3 divide-y">
            <li
              :for={registration <- @registrations}
              id={"registration-#{registration.id}"}
              aria-current={registration.id == @highlighted_booking_id && "true"}
              class={["grid-cols-subgrid col-span-full grid items-center gap-y-3 py-4", registration.id == @highlighted_booking_id && highlighted_row_class()]}
            >
              <div class="col-start-1 row-start-1 min-w-0">
                <p class="text-base-content flex flex-wrap items-center gap-x-2 gap-y-1 font-semibold">
                  <span class="min-w-0 break-words">{registration.name}</span>
                  <span :if={registration.seats_held > 1} class="text-base-content/75 tabular-nums">
                    +{registration.seats_held - 1}
                  </span>
                  <.settlement_badge registration={registration} locale={@locale} />
                </p>
                <a
                  href={fastmail_compose(to: registration.email)}
                  data-app-href={fastmail_app_compose(to: registration.email)}
                  target="_blank"
                  rel="noopener"
                  class="text-base-content/75 block w-fit truncate text-sm pointer-coarse:py-3 hover:underline"
                >
                  {registration.email}
                </a>
                <.refunds registration={registration} locale={@locale} />
              </div>
              <div class="col-start-2 row-start-1 justify-self-end">
                <.registration_actions registration={registration} locale={@locale} />
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
            id="cancelled-bookings"
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
        </section>
      </.admin_page>
      <.cancel_drawer
        title={~t"Cancel booking"}
        submit_label={~t"Cancel booking"}
        keep_label={~t"Keep booking"}
        form={@cancel_form}
        error={@cancel_error}
        email={@cancelling && @cancelling.email}
        locale={@locale}
        preview={@preview}
        swedish_toggle?={@cancelling && @cancelling.locale != "sv-FI"}
      />
      <.email_drawer
        form={@email_form}
        preview={@preview}
        swedish_toggle?={@emailing_id && booking(@course, @emailing_id).locale != "sv-FI"}
        {EmailDrawer.text(@email_kind, @emailing_id && booking(@course, @emailing_id), @locale)}
      />
      <.settlement_drawer
        course={@course}
        registration={@settling_id && booking(@course, @settling_id)}
        mode={@settlement_mode}
        refund_params={@refund_params}
        payment_params={@payment_params}
        error={@settlement_error}
        locale={@locale}
        preview={@preview}
      />
      <.live_component
        :if={!@past?}
        module={ShareLinkDrawer}
        id="share-course-link"
        path={~p"/courses/#{@course.id}"}
        current_user={@current_user}
      />
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("open_settlement", %{"id" => id} = params, socket) do
    registration = booking(socket.assigns.course, id)

    mode =
      if params["mode"] == "refund" or registration.to_refund?,
        do: :refund,
        else: :settle

    {:noreply,
     socket
     |> assign(settling_id: id, settlement_mode: mode, settlement_error: nil)
     |> assign(
       :preview,
       if(mode == :refund,
         do: DrawerPreview.build(:refunded, registration, Map.get(socket.assigns.refund_params, id, %{}))
       )
     )
     |> push_event("js-exec", %{to: "#settlement-drawer", attr: "phx-show"})}
  end

  def handle_event("undo_payment", %{"id" => id, "payment-id" => payment_id}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &PaymentActions.undo_payment(&1, payment_id, actor))
  end

  def handle_event("change_refund", %{"record_id" => id, "refund" => params} = event, socket) do
    params = PaymentActions.refund_params(params, event["_target"])
    preview = DrawerPreview.build(:refunded, booking(socket.assigns.course, id), params)
    {:noreply, socket |> update(:refund_params, &Map.put(&1, id, params)) |> assign(:preview, preview)}
  end

  def handle_event("refund", %{"record_id" => id, "refund" => params}, socket) do
    actor = socket.assigns.current_user
    settle(socket, id, &PaymentActions.refund(&1, params, actor))
  end

  def handle_event("change_payment", %{"record_id" => id, "payment" => params}, socket) do
    preview = DrawerPreview.build(:payment, booking(socket.assigns.course, id), params)
    {:noreply, socket |> update(:payment_params, &Map.put(&1, id, params)) |> assign(:preview, preview)}
  end

  def handle_event("record_payment", %{"record_id" => id, "payment" => params}, socket) do
    actor = socket.assigns.current_user
    socket = update(socket, :payment_params, &Map.put(&1, id, params))
    settle(socket, id, &PaymentActions.record_payment(&1, params, actor))
  end

  def handle_event("open_payment_link", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    with_registration(socket, id, &PaymentActions.open_payment_link(&1, actor))
  end

  def handle_event("open_email", %{"kind" => kind, "id" => id}, socket) do
    registration = booking(socket.assigns.course, id)
    {:noreply, EmailDrawer.open(socket, kind, registration, emailing_id: id)}
  end

  def handle_event("close_email", _params, socket) do
    {:noreply, EmailDrawer.close(socket, emailing_id: nil)}
  end

  def handle_event("validate_email", %{"email" => params}, socket) do
    %{course: course, emailing_id: id} = socket.assigns
    {:noreply, EmailDrawer.validate(socket, params, booking(course, id))}
  end

  def handle_event("send_email", %{"email" => %{"message" => message}}, socket) do
    %{email_kind: kind, emailing_id: id, current_user: actor} = socket.assigns

    socket
    |> EmailDrawer.close(emailing_id: nil)
    |> with_registration(id, &send_email(kind, &1, message, actor))
  end

  def handle_event("remove_seat", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    socket =
      with {:ok, registration} <- Courses.get_registration_by_id(id, actor: actor),
           {:ok, _} <- Courses.remove_registration_seat(registration, actor: actor) do
        put_flash(socket, :success, ~t"Seat removed.")
      else
        _ -> put_flash(socket, :error, ~t"Could not remove the seat.")
      end

    {:noreply, reload_course(socket)}
  end

  def handle_event("open_cancel", %{"id" => id}, socket) do
    registration = booking(socket.assigns.course, id)

    {:noreply,
     socket
     |> assign(cancelling: registration, cancel_form: PaymentActions.cancel_form(registration), cancel_error: nil)
     |> assign(:preview, DrawerPreview.build(:cancelled, registration, PaymentActions.cancel_form(registration).params))
     |> push_event("js-exec", %{to: "#cancel-drawer", attr: "phx-show"})}
  end

  def handle_event("close_cancel", _params, socket) do
    {:noreply, assign(socket, cancelling: nil, cancel_form: nil, cancel_error: nil)}
  end

  def handle_event("validate_cancel", %{"cancel" => params}, socket) do
    {:noreply,
     socket
     |> assign(:cancel_form, to_form(params, as: :cancel))
     |> assign(:preview, DrawerPreview.build(:cancelled, socket.assigns.cancelling, params))}
  end

  def handle_event("submit_cancel", %{"cancel" => params}, socket) do
    socket = assign(socket, :cancel_form, to_form(params, as: :cancel))

    case PaymentActions.cancel(socket.assigns.cancelling, params, socket.assigns.current_user) do
      {:ok, _registration} ->
        {:noreply,
         socket
         |> assign(cancelling: nil, cancel_form: nil, cancel_error: nil)
         |> push_event("js-exec", %{to: "#cancel-drawer", attr: "phx-hide"})
         |> put_flash(:success, ~t"Booking cancelled.")
         |> reload_course()}

      {:error, message} ->
        {:noreply, socket |> assign(:cancel_error, message) |> reload_course()}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "admin:bookings"}, socket), do: {:noreply, reload_course(socket)}

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

    {:noreply, reload_course(socket)}
  end

  # The drawer closes once the money is recorded. On an error it stays open, and the
  # form keeps what Jennie entered because the server never re-renders those inputs.
  defp settle(socket, id, payment_action) do
    socket =
      case Courses.get_registration_by_id(id, actor: socket.assigns.current_user, load: [:balance]) do
        {:ok, registration} ->
          case payment_action.(registration) do
            {:success, message} ->
              settlement_recorded(socket, id, :success, message)

            {:ok, {kind, message}} ->
              settlement_recorded(socket, id, kind, message)

            {:error, message} ->
              assign(socket, :settlement_error, message)
          end

        {:error, _error} ->
          assign(socket, :settlement_error, ~t"Booking not found.")
      end

    {:noreply, reload_course(socket)}
  end

  defp booking(course, id), do: Enum.find(course.bookings, &(&1.id == id))

  defp settlement_recorded(socket, id, kind, message) do
    socket
    |> put_flash(kind, message)
    |> assign(settling_id: nil, settlement_error: nil)
    |> update(:refund_params, &Map.delete(&1, id))
    |> update(:payment_params, &Map.delete(&1, id))
    |> push_event("js-exec", %{to: "#settlement-drawer", attr: "phx-hide"})
  end

  defp send_email(:payment_reminder, registration, message, actor) do
    case Courses.send_registration_payment_reminder(registration, %{message: message}, actor: actor) do
      {:ok, _registration} ->
        {:success, ~t"Payment reminder sent."}

      {:error, error} ->
        Logger.error("Payment reminder for course registration #{registration.id} not sent: #{inspect(error)}")
        {:error, ~t"Could not send the email. Try again in a moment."}
    end
  end

  defp send_email(:payment_link, registration, message, actor),
    do: PaymentActions.email_payment_link(registration, message, actor)

  defp send_email(:confirmation, registration, message, actor) do
    case Courses.email_registration_confirmation(registration, %{message: message}, actor: actor) do
      {:ok, _registration} ->
        {:success, ~t"Confirmation emailed."}

      {:error, error} ->
        Logger.error("Confirmation for course registration #{registration.id} not emailed: #{inspect(error)}")
        {:error, ~t"Could not email the confirmation."}
    end
  end

  defp reload_course(socket) do
    {:ok, socket} = load_course(socket, socket.assigns.course.id)
    socket
  end

  defp load_course(socket, id) do
    load = [
      :seats_booked,
      bookings: [
        :amount_paid,
        :amount_held,
        :balance,
        :to_collect?,
        :to_refund?,
        :refund_methods,
        :default_refund_method,
        :refundable?,
        :seats_held,
        :payment_link_open?,
        :payment_reminder?,
        payments: [:undoable?, :reversal]
      ]
    ]

    case Courses.get_course_by_id(id, actor: socket.assigns.current_user, load: load) do
      {:ok, course} ->
        course = Translations.translate(course)
        {cancelled, registrations} = Enum.split_with(course.bookings, &(&1.status == :cancelled))

        {:ok,
         assign(socket,
           course: course,
           registrations: registrations,
           cancelled_to_refund: Enum.filter(cancelled, & &1.to_refund?),
           cancelled_settled: Enum.reject(cancelled, & &1.to_refund?),
           past?: Date.before?(course.date, Edenflowers.ShopTime.today()),
           bcc: registrations |> Enum.map(& &1.email) |> Enum.uniq() |> Enum.join(",")
         )}

      {:error, _error} ->
        :error
    end
  end

  attr :registration, :map, required: true
  attr :locale, :string, required: true

  defp registration_actions(assigns) do
    ~H"""
    <.actions_menu id={"registration-actions-#{@registration.id}"}>
      <li :if={stripe_payment_intent_id(@registration)}>
        <.link
          href={StripeAPI.dashboard_payment_url(stripe_payment_intent_id(@registration))}
          target="_blank"
          rel="noopener"
        >
          Stripe <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
        </.link>
      </li>
      <.actions_menu_button
        :if={@registration.status == :confirmed}
        menu={"registration-actions-#{@registration.id}"}
        phx-click="open_email"
        phx-value-kind="confirmation"
        phx-value-id={@registration.id}
      >
        {if @registration.confirmation_emailed_at,
          do: ~t"Resend confirmation",
          else: ~t"Email confirmation"}
      </.actions_menu_button>
      <.actions_menu_button
        :if={@registration.to_collect?}
        menu={"registration-actions-#{@registration.id}"}
        phx-click="open_email"
        phx-value-kind="payment_reminder"
        phx-value-id={@registration.id}
      >
        {~t"Send payment reminder"}
      </.actions_menu_button>
      <.actions_menu_button
        :if={@registration.refundable?}
        menu={"registration-actions-#{@registration.id}"}
        phx-click="open_settlement"
        phx-value-id={@registration.id}
        phx-value-mode="refund"
      >
        {~t"Refund"}
      </.actions_menu_button>
      <.actions_menu_button
        :for={payment <- @registration.payments}
        :if={payment.undoable?}
        id={"undo-payment-#{payment.id}"}
        menu={"registration-actions-#{@registration.id}"}
        phx-click="undo_payment"
        phx-value-id={@registration.id}
        phx-value-payment-id={payment.id}
        data-confirm={undo_confirmation(payment, @locale)}
      >
        {undo_label(payment, @locale)}
      </.actions_menu_button>
      <.actions_menu_button
        :if={@registration.seats_held > 1}
        menu={"registration-actions-#{@registration.id}"}
        phx-click="remove_seat"
        phx-value-id={@registration.id}
        data-confirm={remove_seat_confirmation(@registration)}
      >
        {~t"Remove a seat"}
      </.actions_menu_button>
      <.actions_menu_button
        menu={"registration-actions-#{@registration.id}"}
        phx-click="open_cancel"
        phx-value-id={@registration.id}
        class="text-error"
      >
        {dpgettext("admin", "course booking", "Cancel")}
      </.actions_menu_button>
    </.actions_menu>
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

  # A paid booking's PaymentIntent is on its Payment; a pending one's is still on the booking.
  defp stripe_payment_intent_id(registration),
    do: Enum.find_value(registration.payments, & &1.payment_intent_id) || registration.payment_intent_id

  attr :registration, :map, required: true
  attr :locale, :string, required: true

  # Opens the settlement drawer, so the amount owed doubles as the way to settle it.
  defp settlement_badge(assigns) do
    ~H"""
    <.badge
      :if={@registration.to_collect? or @registration.to_refund?}
      id={"settle-#{@registration.id}"}
      type="button"
      tone={if @registration.to_collect?, do: :warning, else: :error}
      class="tabular-nums"
      aria-haspopup="dialog"
      aria-controls="settlement-drawer"
      phx-click="open_settlement"
      phx-value-id={@registration.id}
    >
      {if @registration.to_collect?,
        do: ~t"To collect #{amount = Format.currency(@registration.balance, @locale)}",
        else: ~t"To refund #{amount = Format.currency(Decimal.abs(@registration.balance), @locale)}"}
      <.icon name="hero-chevron-right" class="-mr-0.5 h-3.5 w-3.5 shrink-0" />
    </.badge>
    """
  end

  attr :registration, :map, required: true
  attr :locale, :string, required: true

  # A booking has no history, so its row lists what was handed back.
  defp refunds(assigns) do
    assigns =
      assign(
        assigns,
        :refunds,
        Enum.filter(
          assigns.registration.payments,
          &(Decimal.negative?(&1.amount) and is_nil(&1.reverses_payment_id) and is_nil(&1.reversal))
        )
      )

    ~H"""
    <p :for={refund <- @refunds} class="text-base-content/75 text-sm">
      {~t"Refunded #{amount = Format.currency(Decimal.abs(refund.amount), @locale)} · #{how = OrderLog.payment_method_label(refund.method)}"}
      <span :if={refund.note}>· {refund.note}</span>
    </p>
    """
  end

  defp highlighted_row_class, do: "row-flash scroll-mt-[calc(env(safe-area-inset-top)+6rem)]"

  defp undo_label(payment, locale) do
    amount = Format.currency(Decimal.abs(payment.amount), locale)

    if Decimal.negative?(payment.amount),
      do: ~t"Undo #{amount} refund",
      else: ~t"Undo #{amount} payment"
  end

  defp paid?(registration), do: Decimal.positive?(registration.amount_paid)

  defp remove_seat_confirmation(registration) do
    if paid?(registration) do
      ~t"This does not refund. Refund the seat here afterwards. Remove one seat from this booking?"
    else
      ~t"Remove one seat from this booking?"
    end
  end

  # Jennie uses Fastmail on the web, so compose there rather than via mailto:.
  # Phones open the Fastmail app instead (the script beside email_link/1).
  defp fastmail_compose(params), do: "https://app.fastmail.com/mail/compose?" <> URI.encode_query(params)
  defp fastmail_app_compose(params), do: "fastmail://mail/compose?" <> URI.encode_query(params)
end

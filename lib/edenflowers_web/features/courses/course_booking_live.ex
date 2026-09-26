defmodule EdenflowersWeb.Courses.CourseBookingLive do
  use EdenflowersWeb, :live_view

  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  # Stripe returns guests here too, so the booking is read by its unguessable
  # id rather than through the owner policy. The page shows only what the
  # booker already knows: never the email address.
  def mount(%{"id" => id} = params, _session, socket) do
    payment_failed? = params["redirect_status"] == "failed"

    case load_registration(id) do
      # A redirect-based method (MobilePay) comes back with `redirect_status=failed`
      # when the customer cancels or is declined in the app. Release the seat hold,
      # as "Change booking" does, and send them back to book again.
      {:ok, %{status: :pending} = registration} when payment_failed? ->
        Courses.cancel_registration!(registration, actor: system_actor())

        {:ok,
         socket
         |> put_flash(:error, ~t"Your payment didn't go through. Please try again or choose another payment method.")
         |> push_navigate(to: ~p"/courses/#{registration.course_id}")}

      {:ok, registration} ->
        if connected?(socket) and registration.status == :pending do
          Phoenix.PubSub.subscribe(Edenflowers.PubSub, "course_registration:confirmed:#{id}")
        end

        {:ok, assign(socket, page_title: ~t"Your booking", locale: Format.locale(), registration: registration)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Booking not found.")
         |> push_navigate(to: ~p"/courses")}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: "course_registration:confirmed:" <> id}, socket) do
    {:ok, registration} = load_registration(id)
    {:noreply, assign(socket, registration: registration)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="max-w-xl">
          <.flower name="flower-30" class="text-primary/70 mb-8 h-16 w-16" />
          <%= if @registration.status == :cancelled do %>
            <h1 class="page-title mb-6">{~t"Booking cancelled"}</h1>
            <p class="leading-relaxed">{~t"This booking has been cancelled. Get in touch if that's a surprise."}</p>
          <% else %>
            <h1 class="page-title">{~t"You're booked"}</h1>

            <%!-- Stripe can redirect here before its webhook confirms the booking. A live
          region, so the swap from confirming to received is announced. --%>
            <p role="status" class="text-base-content/70 mt-6 text-sm" data-testid="payment-status">
              <%= if @registration.status == :confirmed do %>
                <.icon name="hero-check-circle" class="text-primary size-4 align-[-0.2em]" />
                {~t"Payment received. A confirmation email is on its way."}
              <% else %>
                {~t"Confirming your payment… You'll get a confirmation email once it's done."}
              <% end %>
            </p>
          <% end %>

          <dl class="border-base-content/12 grid-cols-[auto_1fr] mt-10 grid items-baseline gap-x-6 gap-y-3 border-y py-6">
            <dt class="eyebrow text-base-content/70">{~t"Course"}</dt>
            <dd>{@registration.course.name}</dd>

            <dt class="eyebrow text-base-content/70">{~t"When"}</dt>
            <dd class="tabular-nums">
              {Format.weekday_date(@registration.course.date, @locale)}, {Format.time(
                @registration.course.start_time,
                @locale
              )}–{Format.time(@registration.course.end_time, @locale)}
            </dd>

            <dt class="eyebrow text-base-content/70">{~t"Where"}</dt>
            <dd>
              {@registration.course.location_name}<br />
              <EdenflowersWeb.Courses.CourseLive.maps_link address={@registration.course.location_address} />
            </dd>

            <dt class="eyebrow text-base-content/70">{~t"Places"}</dt>
            <dd class="tabular-nums">{@registration.seats}</dd>

            <dt class="eyebrow text-base-content/70">{~t"Reference"}</dt>
            <dd class="tabular-nums">{@registration.reference}</dd>
          </dl>

          <p class="text-base-content/70 mt-6">
            {~t"Cancel at least 7 days before the course for a full refund: reply to your confirmation email."}
          </p>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp load_registration(id) do
    with {:ok, registration} <- Courses.get_registration_by_id(id, actor: system_actor(), load: [:course]) do
      {:ok, Map.update!(registration, :course, &Translations.translate/1)}
    end
  end
end

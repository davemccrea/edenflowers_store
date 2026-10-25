defmodule EdenflowersWeb.Courses.CourseBookingLive do
  @moduledoc """
  Course booking confirmation page shown after payment, including pending and cancelled outcomes.
  """

  use EdenflowersWeb, :live_view

  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  # Stripe returns guests here too, so the booking is read by its unguessable
  # id rather than through the owner policy. The page shows only what the
  # booker already knows: never the email address.
  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    payment_failed? = params["redirect_status"] == "failed"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "course_registration:paid:#{id}")
    end

    case load_registration(id) do
      # A redirect-based method (MobilePay) comes back with `redirect_status=failed`
      # when the customer cancels or is declined in the app. Discard the unpaid
      # registration, as "Change booking" does, and send them back to book again.
      {:ok, %{committed?: false} = registration} when payment_failed? ->
        Courses.discard_registration!(registration, actor: system_actor())

        {:ok,
         socket
         |> put_flash(:error, ~t"Your payment didn't go through. Please try again or choose another payment method.")
         |> push_navigate(to: ~q"/#{language}/courses/#{registration.course_id}")}

      {:ok, registration} ->
        {:ok, assign(socket, page_title: ~t"Your booking", locale: Format.locale(), registration: registration)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Booking not found.")
         |> push_navigate(to: ~q"/#{language}/courses")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="max-w-xl">
          <.flower name="flower-30" class="text-primary/70 mb-8 h-16 w-16" />
          <%= cond do %>
            <% @registration.cancelled? -> %>
              <h1 class="page-title mb-6">{~t"Booking cancelled"}</h1>
              <p class="leading-relaxed">
                {~t"This booking has been cancelled. If you have any questions, just get in touch."}
              </p>
            <% not @registration.committed? -> %>
              <h1 class="page-title">{~t"Your booking"}</h1>
              <p role="status" class="mt-6 leading-relaxed" data-testid="booking-confirming">
                {~t"Confirming your payment… You'll get a receipt by email once it's done."}
              </p>
            <% true -> %>
              <h1 class="page-title">{~t"You're booked"}</h1>
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

          <p
            :if={@registration.upcoming?}
            class="text-base-content/70 mt-6"
          >
            {~t"To cancel, reply to your confirmation email."} {Edenflowers.Courses.Course.cancellation_terms(
              @registration.course
            )}
          </p>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "course_registration:paid:" <> id}, socket) do
    case load_registration(id) do
      {:ok, registration} -> {:noreply, assign(socket, registration: registration)}
      {:error, _error} -> {:noreply, socket}
    end
  end

  defp load_registration(id) do
    with {:ok, registration} <-
           Courses.get_registration_by_id(id,
             actor: system_actor(),
             load: [:course, :committed?, :cancelled?, :upcoming?]
           ) do
      {:ok, Map.update!(registration, :course, &Translations.translate/1)}
    end
  end
end

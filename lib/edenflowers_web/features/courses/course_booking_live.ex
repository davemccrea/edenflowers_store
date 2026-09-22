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
  def mount(%{"id" => id}, _session, socket) do
    case load_registration(id) do
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
      <.container class="max-w-2xl">
        <%!-- Pending flips to booked while the page is open, when Stripe's webhook lands. --%>
        <div aria-live="polite" aria-atomic="true">
          <h1 class="page-title mb-6" data-testid="booking-status">{heading(@registration.status)}</h1>
          <p class="leading-relaxed">{message(@registration)}</p>
        </div>

        <dl class="border-base-content/12 grid-cols-[auto_1fr] mt-10 grid items-baseline gap-x-6 gap-y-3 border-y py-6">
          <dt class="eyebrow text-base-content/70">{~t"Course"}</dt>
          <dd class="font-serif text-xl">{@registration.course.name}</dd>

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
      </.container>
    </Layouts.app>
    """
  end

  defp load_registration(id) do
    with {:ok, registration} <- Courses.get_registration_by_id(id, actor: system_actor(), load: [:course]) do
      {:ok, Map.update!(registration, :course, &Translations.translate/1)}
    end
  end

  defp heading(:confirmed), do: ~t"You're booked"
  defp heading(:cancelled), do: ~t"Booking cancelled"
  defp heading(_pending), do: ~t"Confirming your payment"

  defp message(%{status: :confirmed}),
    do: ~t"Your confirmation and receipt are on their way to your inbox. See you there!"

  defp message(%{status: :cancelled}), do: ~t"This booking has been cancelled. Get in touch if that's a surprise."

  defp message(_pending),
    do: ~t"This usually takes a few seconds. You'll get a confirmation email as soon as the payment goes through."
end

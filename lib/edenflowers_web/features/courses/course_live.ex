defmodule EdenflowersWeb.Courses.CourseLive do
  use EdenflowersWeb, :live_view

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  defp stripe_publishable_key, do: Application.get_env(:edenflowers, :stripe_publishable_key)

  def mount(%{"id" => id}, _session, socket) do
    case load_course(id) do
      {:ok, course} ->
        {:ok,
         socket
         |> assign(page_title: course.name, locale: Format.locale(), course: course)
         |> assign(booked_places: booked_places(socket.assigns.current_user, course))
         |> assign(registration: nil, client_secret: nil, focus_booking?: false)
         |> assign_form()}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Course not found.")
         |> push_navigate(to: ~p"/courses")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="grid gap-10 md:grid-cols-[minmax(0,480px)_1fr] md:items-start md:gap-16">
          <figure class="bg-cream aspect-[4/5] relative overflow-hidden">
            <.image
              src={@course.image_slug}
              alt={@course.name}
              width={1000}
              height={1250}
              sizes="(min-width: 768px) 480px, 100vw"
              priority
              class="h-full w-full object-cover"
            />
          </figure>

          <div class="flex flex-col gap-8 md:max-w-prose">
            <header>
              <.link
                navigate={~p"/courses"}
                class="eyebrow text-base-content/70 link-underline-hover mb-5 inline-block w-fit"
              >
                {~t"Courses"}
              </.link>
              <h1 class="page-title" data-testid="course-name">{@course.name}</h1>
            </header>

            <p class="leading-relaxed">{@course.description}</p>

            <dl class="border-base-content/12 grid-cols-[auto_1fr] grid items-baseline gap-x-6 gap-y-3 border-y py-6">
              <dt class="eyebrow text-base-content/70">{~t"When"}</dt>
              <dd class="tabular-nums">
                {Format.weekday_date(@course.date, @locale)}, {Format.time(@course.start_time, @locale)}–{Format.time(
                  @course.end_time,
                  @locale
                )}
              </dd>

              <dt class="eyebrow text-base-content/70">{~t"Where"}</dt>
              <dd>
                {@course.location_name}<br />
                <.maps_link address={@course.location_address} />
              </dd>

              <dt class="eyebrow text-base-content/70">{~t"Price"}</dt>
              <dd class="tabular-nums">{~t"#{price = Format.price(@course.price, @locale)} per person"}</dd>

              <dt class="eyebrow text-base-content/70">{~t"Places"}</dt>
              <dd data-testid="seats-left">{availability(@course)}</dd>

              <dt :if={@course.booking_open?} class="eyebrow text-base-content/70">{~t"Book by"}</dt>
              <dd :if={@course.booking_open?}>{Format.weekday_date(@course.register_before, @locale)}</dd>
            </dl>

            <p :if={@booked_places > 0} data-testid="already-booked">
              {~t"You have #{count = @booked_places} place(s) on this course."N}
              <.link navigate={~p"/account#courses-heading"} class="link-underline-hover">
                {~t"See your bookings"}
              </.link>
            </p>

            <section :if={!@course.booking_open?} data-testid="booking-closed">
              <p>
                {~t"This course is no longer taking bookings. I announce new dates in the newsletter first."}
              </p>
              <.button href="#newsletter" variant="text" class="mt-4">{~t"Sign up for the newsletter"}</.button>
            </section>

            <section :if={@course.booking_open? && is_nil(@registration)} aria-labelledby="book-heading">
              <%!-- Focused only when returning from "Change booking", whose button has just gone. --%>
              <h2
                id="book-heading"
                tabindex="-1"
                phx-mounted={@focus_booking? && JS.focus()}
                class="section-title mb-6 focus-visible:outline-none"
              >
                {if @booked_places > 0, do: ~t"Book another place", else: ~t"Book a place"}
              </h2>
              <.form
                id="booking-form"
                for={@form}
                phx-change="validate"
                phx-submit="book"
                class="flex flex-col gap-6"
                data-testid="booking-form"
              >
                <.input label={~t"Your name *"} field={@form[:name]} type="text" autocomplete="name" aria-required="true" />
                <.input label={~t"Email *"} field={@form[:email]} type="email" autocomplete="email" aria-required="true" />

                <%!-- Errors about the booking as a whole have no field of their own to sit under. --%>
                <.error :for={msg <- Enum.map(@form[:course_id].errors, &translate_error/1)}>{msg}</.error>

                <.form_button data-testid="book-button">
                  {~t"Continue to payment"} · {Format.currency(@course.price, @locale)}
                </.form_button>
              </.form>

              <p class="text-base-content/70 mt-4">{~t"Cancel at least 7 days before the course for a full refund."}</p>
            </section>

            <section :if={@registration} aria-labelledby="pay-heading" data-testid="payment-section">
              <%!-- The booking form, and the button that submitted it, are gone: focus lands here instead of on <body>. --%>
              <h2
                id="pay-heading"
                tabindex="-1"
                phx-mounted={JS.focus()}
                class="section-title mb-4 focus-visible:outline-none"
              >
                {~t"Payment"}
              </h2>
              <p>{~t"One place for #{name = @registration.name}"}</p>
              <button
                type="button"
                phx-click="change"
                class="link-underline-hover text-base-content/70 mb-3 block py-2.5"
              >
                {~t"Change booking"}
              </button>

              <form
                :if={@client_secret}
                id="course-payment-form"
                phx-hook="Stripe"
                phx-submit="pay"
                data-client-secret={@client_secret}
                data-publishable-key={stripe_publishable_key()}
                data-return-url={url(~p"/courses/bookings/#{@registration.id}")}
                data-billing-name={@registration.name}
                data-billing-email={@registration.email}
                data-stripe-loading={JS.set_attribute({"disabled", "true"}, to: "#payment-button")}
                data-stripe-ready={JS.remove_attribute("disabled", to: "#payment-button")}
                class="flex flex-col gap-4"
              >
                <div phx-update="ignore" id="payment-element"></div>
                <p phx-update="ignore" id="stripe-error-message" role="alert" class="text-error"></p>

                <.form_button disabled={true} id="payment-button">
                  {~t"Pay"} {Format.currency(@registration.amount, @locale)}
                </.form_button>
              </form>
            </section>
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("book", %{"form" => params}, socket) do
    with {:ok, registration} <- AshPhoenix.Form.submit(socket.assigns.form, params: params),
         {:ok, registration, client_secret} <- Courses.Payment.setup_payment(registration) do
      {:noreply, assign(socket, registration: registration, client_secret: client_secret)}
    else
      {:error, %Phoenix.HTML.Form{} = form} ->
        {:noreply, socket |> assign(form: form) |> reload_course()}

      {:error, _stripe_reason} ->
        {:noreply,
         socket
         |> put_flash(:error, ~t"Payment is temporarily unavailable. Please try again in a moment.")
         |> release_hold()}
    end
  end

  def handle_event("pay", _params, socket) do
    {:noreply, push_event(socket, "stripe:process_payment", %{})}
  end

  # A fresh booking replaces this one, so its hold must not keep the place.
  def handle_event("change", _params, socket) do
    {:noreply, socket |> release_hold() |> reload_course() |> assign_form() |> assign(focus_booking?: true)}
  end

  def handle_event("stripe:error", %{"message" => message, "details" => details}, socket) do
    Logger.error(
      "Stripe client error for course registration #{socket.assigns.registration.id}: #{message}: #{inspect(details)}"
    )

    {:noreply,
     put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please refresh the page and try again.")}
  end

  defp booked_places(nil, _course), do: 0

  defp booked_places(user, course) do
    Courses.list_my_registrations!(actor: user, query: [filter: [course_id: course.id]])
    |> length()
  end

  defp load_course(id) do
    with {:ok, course} <- Courses.get_course_by_id(id, load: [:seats_left, :booking_open?]) do
      {:ok, Translations.translate(course)}
    end
  end

  defp reload_course(socket) do
    case load_course(socket.assigns.course.id) do
      {:ok, course} ->
        assign(socket, course: course)

      {:error, _} ->
        socket
        |> put_flash(:error, ~t"Course not found.")
        |> push_navigate(to: ~p"/courses")
    end
  end

  defp release_hold(%{assigns: %{registration: nil}} = socket), do: socket

  defp release_hold(socket) do
    Courses.cancel_registration!(socket.assigns.registration, actor: system_actor())
    assign(socket, registration: nil, client_secret: nil)
  end

  defp assign_form(socket) do
    user = socket.assigns.current_user
    course_id = socket.assigns.course.id
    locale = to_string(socket.assigns.locale)

    form =
      CourseRegistration
      |> AshPhoenix.Form.for_create(:register,
        as: "form",
        actor: user,
        params: %{
          "name" => user && user.name,
          "email" => user && to_string(user.email)
        },
        transform_params: fn _form, params, _action ->
          Map.merge(params, %{"course_id" => course_id, "locale" => locale})
        end
      )
      |> to_form()

    assign(socket, form: form)
  end

  defp availability(%{seats_left: seats_left}) when seats_left <= 0, do: ~t"Fully booked"
  defp availability(%{seats_left: seats_left}), do: ~t"#{count = seats_left} place(s) left"N

  attr :address, :string, required: true

  def maps_link(assigns) do
    ~H"""
    <a
      href={"https://www.google.com/maps/search/?api=1&query=" <> URI.encode_www_form(@address)}
      target="_blank"
      rel="noreferrer"
      class="link-underline-hover"
    >
      {@address}<span class="sr-only">{~t"(opens a map in a new tab)"}</span>
    </a>
    """
  end
end

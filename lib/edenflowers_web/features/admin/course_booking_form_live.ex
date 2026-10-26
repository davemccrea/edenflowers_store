defmodule EdenflowersWeb.Admin.CourseBookingFormLive do
  @moduledoc "Admin page for accepting a course booking and choosing how it will be paid."
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.Drawers, only: [customer_email: 1]

  alias Edenflowers.Courses.Course
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email.Preview
  alias Edenflowers.Format
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ash.get(Course, id, actor: socket.assigns.current_user) do
      {:ok, course} ->
        form =
          AshPhoenix.Form.for_create(CourseRegistration, :add_manually,
            actor: socket.assigns.current_user,
            params: %{"email_customer?" => "true", "payment_terms" => "on_fulfillment"},
            transform_params: fn _form, params, _action ->
              Map.put(params, "course_id", course.id)
            end
          )
          |> to_form()

        {:ok,
         socket
         |> assign(:course, course)
         |> assign(:page_title, ~t"Add booking")
         |> assign(:locale, Localize.get_locale())
         |> assign_form(form)}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, ~t"Course not found.") |> push_navigate(to: ~p"/admin/courses")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={@page_title} back={{@course.name, ~p"/admin/courses/#{@course.id}"}} sticky>
          <:subtitle>
            <span id="booking-course" class="flex flex-col gap-1">
              <span class="text-base-content text-base font-semibold">{@course.name}</span>
              <span class="tabular-nums">
                {Format.date(@course.date, @locale)} · {Format.time(@course.start_time, @locale)}–{Format.time(
                  @course.end_time,
                  @locale
                )} · {@course.location_name}
              </span>
            </span>
          </:subtitle>
          <:actions>
            <.button navigate={~p"/admin/courses/#{@course.id}"} variant="secondary" size="sm">{~t"Cancel"}</.button>
            <.button type="submit" form="booking-form" variant="primary" size="sm">{~t"Add booking"}</.button>
          </:actions>
        </.admin_page_header>

        <.form
          for={@form}
          id="booking-form"
          phx-change="validate"
          phx-submit="save"
          data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
          class="admin-card divide-base-content/12 max-w-3xl divide-y"
        >
          <.form_section title={~t"Booking details"} joined>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@form[:name]} type="text" label={~t"Name"} class="input w-full" />
              <.input field={@form[:email]} type="email" label={~t"Email"} class="input w-full" />
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
                label={~t"Email language"}
                options={[{"Svenska", "sv-FI"}, {"Suomi", "fi"}, {"English", "en-GB"}]}
                class="select w-full"
              />
            </div>
          </.form_section>

          <.form_section title={~t"Payment"} joined>
            <div class="space-y-4">
              <.input
                :let={option}
                field={@form[:payment_terms]}
                type="radio-card"
                options={[
                  %{value: "payment_link", label: ~t"Payment link"},
                  %{value: "invoice", label: ~t"Invoice"},
                  %{value: "on_fulfillment", label: ~t"In person"}
                ]}
              >
                {option.label}
              </.input>
              <p :if={@form[:payment_terms].value in [:payment_link, "payment_link"]} class="text-base-content/75 text-sm">
                {~t"A payment link will be created and included if you email the booking confirmation."}
              </p>
              <p :if={@form[:payment_terms].value in [:invoice, "invoice"]} class="text-base-content/75 text-sm">
                {~t"Send the invoice separately. Record the payment here once it arrives."}
              </p>
            </div>
          </.form_section>

          <.form_section title={~t"Confirmation"} joined>
            <.customer_email
              id="booking-email"
              send={@form[:email_customer?]}
              label={~t"Email booking confirmation to the customer"}
              message={@form[:message]}
              preview={@preview}
              collapse_preview?={true}
              in_swedish={@form[:locale].value != "sv-FI" && @form[:in_swedish]}
            />
          </.form_section>
        </.form>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign_form(socket, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _registration} ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Booking added.")
         |> push_navigate(to: ~p"/admin/courses/#{socket.assigns.course.id}")}

      {:error, form} ->
        {:noreply, assign_form(socket, form)}
    end
  end

  defp assign_form(socket, form) do
    form = to_form(form)

    preview =
      if form[:email_customer?].value in [true, "true"] and form[:email].value not in [nil, ""] do
        locale = if form[:in_swedish].value == "true", do: "sv-FI"

        Preview.build_entered_booking(
          form.source.source,
          socket.assigns.course,
          %{message: form[:message].value},
          locale
        )
      end

    assign(socket, form: form, preview: preview)
  end
end

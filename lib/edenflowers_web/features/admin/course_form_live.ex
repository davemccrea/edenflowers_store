defmodule EdenflowersWeb.Admin.CourseFormLive do
  @moduledoc """
  Admin form to create or edit a course and its translations.
  """

  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.PhotoUpload, only: [photo_input: 1]
  import EdenflowersWeb.Admin.TranslationFields

  alias Edenflowers.Courses.Course
  alias Edenflowers.Pricing
  alias EdenflowersWeb.Admin.PhotoUpload
  alias EdenflowersWeb.Admin.TranslationFields
  alias EdenflowersWeb.Layouts

  @photo_fields ["form[image_slug]"]

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case load_form(params, actor) do
      {:ok, title, form} ->
        {:ok,
         socket
         |> assign(:page_title, title)
         |> assign(:tax_rates, Pricing.list_selectable_tax_rates!(actor: actor))
         |> assign(:form, form)
         |> assign(:translating, nil)
         |> PhotoUpload.allow(@photo_fields)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Course not found.")
         |> push_navigate(to: ~p"/admin/courses")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={@page_title} back={form_back(@form)} sticky>
          <:actions>
            <.button
              :if={@form.source.type == :update}
              href={~q"/#{language}/courses/#{@form.source.data.id}"}
              target="_blank"
              variant="secondary"
              size="sm"
              class="max-md:btn-square"
            >
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
              <span class="max-md:sr-only">{~t"View in store"}</span>
            </.button>
            <.button type="submit" form="course-form" variant="primary" size="sm">
              {~t"Save"}
            </.button>
          </:actions>
        </.admin_page_header>

        <.form
          for={@form}
          id="course-form"
          data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
          phx-change="validate"
          phx-submit="save"
          class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start"
        >
          <div class="space-y-6">
            <.form_section title={~t"Name and description"}>
              <.language_fields form={@form} translating={@translating} />
            </.form_section>

            <.form_section title={~t"When"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input field={@form[:date]} type="date" label={~t"Date"} class="input w-full" />
                <.input
                  field={@form[:register_before]}
                  type="date"
                  label={~t"Book by"}
                  class="input w-full"
                />
                <.input field={@form[:start_time]} type="time" label={~t"Starts"} class="input w-full" />
                <.input field={@form[:end_time]} type="time" label={~t"Ends"} class="input w-full" />
              </div>
            </.form_section>

            <.form_section title={~t"Seats and price"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@form[:total_places]}
                  type="number"
                  min="1"
                  label={~t"Seats"}
                  class="input w-full tabular-nums"
                />
                <.input
                  field={@form[:price]}
                  type="text"
                  inputmode="decimal"
                  label={~t"Price per seat (€)"}
                  class="input w-full tabular-nums"
                />
                <.input
                  field={@form[:tax_rate_id]}
                  type="select"
                  label={~t"VAT"}
                  options={Enum.map(@tax_rates, &{&1.name, &1.id})}
                  class="select w-full"
                />
              </div>
            </.form_section>

            <.form_section title={~t"Cancellation"}>
              <:description>
                {~t"Shown on the course page and in the booking emails, and used to fill in a cancelled booking's refund."}
              </:description>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@form[:cancellation_days]}
                  type="number"
                  min="0"
                  label={~t"Full refund until (days before)"}
                  class="input w-full tabular-nums"
                />
                <.input
                  field={@form[:cancellation_fee_percent]}
                  type="number"
                  min="0"
                  max="100"
                  label={~t"Kept after that (%)"}
                  class="input w-full tabular-nums"
                />
              </div>
            </.form_section>

            <.form_section title={~t"Taught in"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@form[:language]}
                  type="select"
                  label={~t"Language"}
                  options={[{~t"Swedish", :sv}, {~t"Finnish", :fi}, {~t"English", :en}]}
                  class="select w-full"
                />
              </div>
            </.form_section>

            <.form_section title={~t"Where"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input field={@form[:location_name]} type="text" label={~t"Venue"} class="input w-full" />
                <.input field={@form[:location_address]} type="text" label={~t"Address"} class="input w-full" />
              </div>
            </.form_section>
          </div>

          <aside class="flex flex-col gap-6">
            <.form_section title={~t"Photo"}>
              <.photo_input
                field={@form[:image_slug]}
                uploads={@uploads}
                label={~t"Photo"}
                show_errors={@form.source.submitted_once?}
              />
            </.form_section>
          </aside>
        </.form>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    params = PhotoUpload.merge_slugs(params, socket, @photo_fields)
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("translate", %{"from" => from}, socket),
    do: {:noreply, TranslationFields.translate(socket, from)}

  def handle_event("save", %{"form" => params}, socket) do
    socket = PhotoUpload.store_uploads(socket, @photo_fields)
    params = PhotoUpload.merge_slugs(params, socket, @photo_fields)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Course saved.")
         |> push_navigate(to: saved_path(socket.assigns.form, course))}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, ~t"The course wasn't saved. Check the fields marked below.")}
    end
  end

  @impl true
  def handle_async(:translate, result, socket),
    do: {:noreply, TranslationFields.put_translations(socket, result)}

  # A new course has no bookings yet, and adding them is what comes next.
  defp saved_path(%{source: %{type: :create}}, course), do: ~p"/admin/courses/#{course.id}"
  defp saved_path(_form, course), do: ~p"/admin/courses/#{course.id}/edit"

  defp form_back(%{source: %{type: :create}}), do: {~t"Courses", ~p"/admin/courses"}
  defp form_back(%{source: %{data: course}}), do: {course.name, ~p"/admin/courses/#{course.id}"}

  defp load_form(%{"id" => id}, actor) do
    case Ash.get(Course, id, actor: actor) do
      {:ok, course} ->
        form = AshPhoenix.Form.for_update(course, :update, actor: actor) |> TranslationFields.add_forms()
        {:ok, course.name, to_form(form)}

      {:error, _} ->
        :error
    end
  end

  defp load_form(_params, actor) do
    form = AshPhoenix.Form.for_create(Course, :create, actor: actor) |> TranslationFields.add_forms()
    {:ok, ~t"New course", to_form(form)}
  end
end

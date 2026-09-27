defmodule EdenflowersWeb.Admin.CourseFormLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.PhotoUpload, only: [photo_input: 1]
  import EdenflowersWeb.Admin.TranslationFields

  alias EdenflowersWeb.Admin.PhotoUpload
  alias EdenflowersWeb.Admin.TranslationFields
  alias EdenflowersWeb.Layouts
  alias Edenflowers.Courses.Course
  alias Edenflowers.Pricing.TaxRate

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @photo_fields ["form[image_slug]"]

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case load_form(params, actor) do
      {:ok, title, form} ->
        {:ok,
         socket
         |> assign(:page_title, title)
         |> assign(:tax_rates, Ash.read!(TaxRate, actor: actor))
         |> assign(:form, form)
         |> PhotoUpload.allow(@photo_fields)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Course not found.")
         |> push_navigate(to: ~p"/admin/courses")}
    end
  end

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

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    params = PhotoUpload.merge_slugs(params, socket, @photo_fields)
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    socket = PhotoUpload.store_uploads(socket, @photo_fields)
    params = PhotoUpload.merge_slugs(params, socket, @photo_fields)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _course} ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Course saved")
         |> push_navigate(to: ~p"/admin/courses")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="wide">
        <.admin_page_header title={@page_title} back={~p"/admin/courses"} back_label={~t"Courses"} />

        <.form
          for={@form}
          id="course-form"
          phx-change="validate"
          phx-submit="save"
          class="grid grid-cols-1 gap-x-10 gap-y-10 lg:grid-cols-[minmax(0,1fr)_16rem]"
        >
          <div class="space-y-10">
            <.form_section title={~t"Name and description"}>
              <.language_fields form={@form} />
            </.form_section>

            <.form_section title={~t"When"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                <.input field={@form[:date]} type="date" label={~t"Date"} class="input w-full" />
                <.input field={@form[:start_time]} type="time" label={~t"Starts"} class="input w-full" />
                <.input field={@form[:end_time]} type="time" label={~t"Ends"} class="input w-full" />
                <.input
                  field={@form[:register_before]}
                  type="date"
                  label={~t"Book by"}
                  help={~t"Online booking closes after this day."}
                  class="input w-full"
                />
              </div>
            </.form_section>

            <.form_section title={~t"Seats and price"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
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

            <.form_section title={~t"Where"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input field={@form[:location_name]} type="text" label={~t"Venue"} class="input w-full" />
                <.input field={@form[:location_address]} type="text" label={~t"Address"} class="input w-full" />
              </div>
            </.form_section>
          </div>

          <aside class="space-y-10 lg:sticky lg:top-6 lg:self-start">
            <.form_section title={~t"Photo"}>
              <.photo_input
                field={@form[:image_slug]}
                uploads={@uploads}
                label={~t"Photo"}
                show_errors={@form.source.submitted_once?}
              />
            </.form_section>

            <.button type="submit" variant="primary" class="w-full">{~t"Save course"}</.button>
          </aside>
        </.form>
      </.admin_page>
    </Layouts.admin>
    """
  end
end

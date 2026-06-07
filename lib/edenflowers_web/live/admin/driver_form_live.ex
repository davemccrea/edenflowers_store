defmodule EdenflowersWeb.Admin.DriverFormLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Delivery.Driver
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:locale, Localize.get_locale())
      |> assign_form(params)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="narrow">
        <.admin_page_header
          title={if @editing, do: ~t"Edit driver", else: ~t"Add driver"}
          back={~p"/admin/drivers"}
          back_label={~t"Drivers"}
        />

        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class="flex flex-col gap-4">
            <.input
              field={@form[:name]}
              id="driver-name"
              type="text"
              label={~t"Name"}
              class="input w-full"
              autofocus
            />
            <.input field={@form[:phone]} type="tel" label={~t"Phone"} class="input w-full" />
            <.input field={@form[:email]} type="email" label={~t"Email"} class="input w-full" />
            <.input
              field={@form[:locale]}
              type="select"
              label={~t"Preferred language"}
              options={locale_options()}
              class="select w-full"
            />
          </div>
          <div class="mt-6 flex justify-end gap-2">
            <.link navigate={~p"/admin/drivers"} class="btn btn-ghost btn-sm">{~t"Cancel"}</.link>
            <button type="submit" class="btn btn-primary btn-sm">{~t"Save"}</button>
          </div>
        </.form>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _driver} ->
        message = if socket.assigns.editing, do: ~t"Driver updated.", else: ~t"Driver added."

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/admin/drivers")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp assign_form(socket, %{"id" => id}) do
    case Ash.get(Driver, id, actor: socket.assigns.current_user) do
      {:ok, driver} ->
        socket
        |> assign(:page_title, ~t"Edit driver")
        |> assign(:editing, true)
        |> assign(:form, AshPhoenix.Form.for_update(driver, :update, actor: socket.assigns.current_user) |> to_form())

      {:error, _} ->
        socket
        |> put_flash(:error, ~t"Driver not found.")
        |> push_navigate(to: ~p"/admin/drivers")
    end
  end

  defp assign_form(socket, _params) do
    socket
    |> assign(:page_title, ~t"Add driver")
    |> assign(:editing, false)
    |> assign(:form, AshPhoenix.Form.for_create(Driver, :create, actor: socket.assigns.current_user) |> to_form())
  end

  defp locale_options, do: [{~t"English", "en-GB"}, {~t"Swedish", "sv-FI"}, {~t"Finnish", "fi"}]
end

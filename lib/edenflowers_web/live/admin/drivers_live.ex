defmodule EdenflowersWeb.Admin.DriversLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Delivery.Driver

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Drivers")
     |> assign(:locale, Localize.get_locale())
     |> load_drivers()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="full">
        <.admin_page_header title={~t"Drivers"}>
          <:subtitle>{~t"People who deliver orders. Each driver has a private link to their route."}</:subtitle>
          <:actions>
            <.link navigate={~p"/admin/drivers/new"} class="btn btn-primary btn-sm">
              <.icon name="hero-plus" class="h-4 w-4" /> {~t"Add driver"}
            </.link>
          </:actions>
        </.admin_page_header>

        <div :if={@drivers == []} class="border-base-300/70 rounded-lg border border-dashed p-10 text-center">
          <p class="text-base-content/65 text-sm">{~t"No drivers yet. Add one to start planning deliveries."}</p>
        </div>

        <div :if={@drivers != []} class="border-base-300/70 overflow-x-auto rounded-lg border">
          <table class="table">
            <thead>
              <tr>
                <th>{~t"Name"}</th>
                <th>{~t"Contact"}</th>
                <th>{~t"Language"}</th>
                <th>{~t"Status"}</th>
                <th class="text-right">{~t"Actions"}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={driver <- @drivers} class={[not driver.active? && "opacity-55"]}>
                <td class="font-medium">{driver.name}</td>
                <td>
                  <div class="flex flex-col gap-0.5 text-sm">
                    <a :if={driver.phone} href={"tel:#{driver.phone}"} class="link link-hover">
                      {driver.phone}
                    </a>
                    <a :if={driver.email} href={"mailto:#{driver.email}"} class="link link-hover text-base-content/65">
                      {driver.email}
                    </a>
                    <span :if={is_nil(driver.phone) and is_nil(driver.email)} class="text-base-content/30">—</span>
                  </div>
                </td>
                <td>{locale_label(driver.locale)}</td>
                <td>
                  <span :if={driver.active?} class="badge badge-sm badge-success admin-badge-success">
                    {~t"Active"}
                  </span>
                  <span :if={not driver.active?} class="badge badge-sm admin-badge-neutral">
                    {~t"Inactive"}
                  </span>
                </td>
                <td>
                  <div class="flex flex-wrap items-center justify-end gap-1">
                    <button
                      type="button"
                      id={"copy-#{driver.id}"}
                      phx-hook="CopyToClipboard"
                      data-clipboard-text={driver_link(driver)}
                      data-copied-label={~t"Copied!"}
                      class="btn btn-ghost btn-xs"
                    >
                      <.icon name="hero-link" class="h-3.5 w-3.5" />
                      <span data-copy-label>{~t"Copy link"}</span>
                    </button>
                    <.link navigate={~p"/admin/drivers/#{driver.id}/edit"} class="btn btn-ghost btn-xs">
                      {~t"Edit"}
                    </.link>
                    <button
                      type="button"
                      phx-click="regenerate_token"
                      phx-value-id={driver.id}
                      data-confirm={~t"Regenerate this driver's link? The current link will stop working."}
                      class="btn btn-ghost btn-xs"
                    >
                      {~t"Regenerate link"}
                    </button>
                    <button
                      :if={driver.active?}
                      type="button"
                      phx-click="deactivate"
                      phx-value-id={driver.id}
                      data-confirm={~t"Deactivate this driver? They won't be available for new routes."}
                      class="btn btn-ghost btn-xs text-error"
                    >
                      {~t"Deactivate"}
                    </button>
                    <button
                      :if={not driver.active?}
                      type="button"
                      phx-click="activate"
                      phx-value-id={driver.id}
                      class="btn btn-ghost btn-xs"
                    >
                      {~t"Reactivate"}
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("regenerate_token", %{"id" => id}, socket) do
    driver = Enum.find(socket.assigns.drivers, &(&1.id == id))

    case Driver.regenerate_token(driver, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, ~t"Link regenerated. The old link no longer works.") |> load_drivers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not regenerate the link.")}
    end
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    driver = Enum.find(socket.assigns.drivers, &(&1.id == id))
    update_active_status(socket, Driver.deactivate(driver, actor: socket.assigns.current_user))
  end

  def handle_event("activate", %{"id" => id}, socket) do
    driver = Enum.find(socket.assigns.drivers, &(&1.id == id))
    update_active_status(socket, Driver.activate(driver, actor: socket.assigns.current_user))
  end

  defp update_active_status(socket, result) do
    case result do
      {:ok, _} -> {:noreply, load_drivers(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, ~t"Could not update the driver.")}
    end
  end

  defp load_drivers(socket) do
    drivers = Driver.list!(query: [sort: [active?: :desc, name: :asc]], actor: socket.assigns.current_user)
    assign(socket, :drivers, drivers)
  end

  defp driver_link(driver), do: EdenflowersWeb.Endpoint.url() <> "/d/" <> driver.link_token

  defp locale_label("en-GB"), do: ~t"English"
  defp locale_label("sv-FI"), do: ~t"Swedish"
  defp locale_label("fi"), do: ~t"Finnish"
  defp locale_label(other), do: to_string(other)
end

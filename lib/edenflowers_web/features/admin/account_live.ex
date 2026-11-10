defmodule EdenflowersWeb.Admin.AccountLive do
  @moduledoc """
  Admin account settings: profile picture and back office colour, then this
  device's language and push notifications.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  require Logger

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.AppearancePicker
  import EdenflowersWeb.Admin.DeviceSettings

  alias Edenflowers.Accounts
  alias Edenflowers.Events
  alias EdenflowersWeb.Admin.PubSub
  alias EdenflowersWeb.Admin.PushSubscriptions

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe(Events.admin_customer(socket.assigns.current_user.id))

    {:ok,
     socket
     |> assign(:stale, false)
     |> assign(:page_title, ~t"Account")
     |> assign(:vapid_public_key, Edenflowers.WebPush.public_key())
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png .webp),
       max_file_size: 2_000_000,
       auto_upload: true,
       progress: &handle_avatar_progress/3
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.stale_editor_notice stale={@stale} />
        <.admin_page_header title={~t"Account"} />

        <section class="admin-card p-4 sm:p-5">
          <div class="mb-5 flex items-center gap-3">
            <img
              :if={@current_user.avatar_content_type}
              src={~p"/admin/account/avatar"}
              alt=""
              class="h-12 w-12 shrink-0 rounded-full object-cover"
            />
            <span
              :if={!@current_user.avatar_content_type}
              class="bg-primary/10 text-primary inline-flex h-12 w-12 shrink-0 items-center justify-center rounded-full text-base font-semibold"
            >
              {@current_user.initials}
            </span>
            <div class="min-w-0">
              <h2 class="text-base-content truncate text-lg font-semibold">
                {@current_user.name || to_string(@current_user.email)}
              </h2>
              <p :if={@current_user.name} class="text-base-content/75 truncate text-sm">
                {to_string(@current_user.email)}
              </p>
            </div>
          </div>

          <dl class="divide-base-content/12 divide-y">
            <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
              <dt class="text-base-content/75 text-sm sm:pt-1.5">{~t"Picture"}</dt>
              <dd>
                <form id="avatar-form" phx-change="validate_avatar" class="grid gap-2">
                  <div class="flex items-center gap-2">
                    <label class="border-base-content/12 flex cursor-pointer items-center gap-2.5 border py-1.5 pr-3 pl-1.5 text-sm transition-colors focus-within:outline-primary focus-within:outline-2 focus-within:outline-offset-2 hover:bg-base-200">
                      <span class="bg-base-200 inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full">
                        <.icon name="hero-camera" class="h-4 w-4" />
                      </span>
                      {if @current_user.avatar_content_type,
                        do: ~t"Change picture",
                        else: ~t"Add picture"}
                      <.live_file_input
                        upload={@uploads.avatar}
                        class="sr-only"
                        aria-describedby="avatar-help"
                        aria-invalid={to_string(avatar_errors(@uploads.avatar) != [])}
                      />
                    </label>
                    <.button
                      :if={@current_user.avatar_content_type}
                      type="button"
                      phx-click="remove_avatar"
                      variant="destructive"
                    >
                      {~t"Remove"}
                    </.button>
                  </div>
                  <progress
                    :for={entry <- Enum.filter(@uploads.avatar.entries, & &1.valid?)}
                    class="progress progress-primary w-full sm:max-w-xs"
                    value={entry.progress}
                    max="100"
                  />
                  <p id="avatar-help" class="text-sm" aria-live="polite">
                    <span :if={avatar_errors(@uploads.avatar) == []} class="text-base-content/75">
                      {~t"JPG, PNG or WebP, up to 2 MB."}
                    </span>
                    <span :for={err <- avatar_errors(@uploads.avatar)} class="text-error block">
                      {avatar_error(err)}
                    </span>
                  </p>
                </form>
              </dd>
            </div>
            <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
              <dt class="text-base-content/75 text-sm sm:pt-1.5">{~t"Colour"}</dt>
              <dd><.appearance_picker user={@current_user} /></dd>
            </div>
          </dl>
        </section>

        <.device_settings current_path={@current_path} vapid_public_key={@vapid_public_key} />

        <div class="mt-6">
          <.button href={~p"/sign-out"} method="delete" variant="secondary" size="sm">
            <.icon name="hero-arrow-right-start-on-rectangle" class="h-4 w-4" />
            {~t"Sign out"}
          </.button>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("reload_editor", _params, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/admin/account")}

  def handle_event("validate_avatar", _params, socket), do: {:noreply, socket}

  def handle_event("push_subscribed", params, socket),
    do: {:reply, PushSubscriptions.subscribe(params, socket.assigns.current_user), socket}

  def handle_event("push_unsubscribed", params, socket),
    do: {:reply, PushSubscriptions.unsubscribe(params, socket.assigns.current_user), socket}

  def handle_event("update_appearance", params, socket) do
    user = socket.assigns.current_user
    attrs = Map.take(params, ["admin_hue", "admin_chroma", "admin_lightness", "admin_grain"])

    case Accounts.update_admin_appearance(user, attrs, actor: user) do
      {:ok, user} ->
        {:noreply, assign(socket, current_user: user, stale: false)}

      {:error, error} ->
        Logger.error("Admin appearance of user #{user.id} not saved: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"Could not save the appearance.")}
    end
  end

  def handle_event("remove_avatar", _params, socket) do
    user = socket.assigns.current_user

    case Accounts.remove_avatar(user, actor: user) do
      {:ok, _user} ->
        {:noreply, redirect(socket, to: ~p"/admin/account")}

      {:error, error} ->
        Logger.error("Profile picture of user #{user.id} not removed: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"Could not remove the profile picture.")}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{} = notification, socket),
    do: {:noreply, PubSub.mark_stale(socket, notification)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp handle_avatar_progress(:avatar, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_avatar_progress(:avatar, entry, socket) do
    user = socket.assigns.current_user

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, Accounts.update_avatar(user, File.read!(path), entry.client_name, actor: user)}
      end)

    case result do
      # A full reload so the browser refetches the image at the unchanged URL.
      {:ok, _user} ->
        {:noreply, redirect(socket, to: ~p"/admin/account")}

      {:error, error} ->
        Logger.error("Profile picture of user #{user.id} not saved: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"Could not save the profile picture.")}
    end
  end

  defp avatar_errors(upload),
    do: upload_errors(upload) ++ Enum.flat_map(upload.entries, &upload_errors(upload, &1))

  defp avatar_error(:too_large), do: ~t"The picture must be under 2 MB."
  defp avatar_error(:not_accepted), do: ~t"Use a JPG, PNG or WebP image."
  defp avatar_error(_), do: ~t"Could not upload the picture."
end

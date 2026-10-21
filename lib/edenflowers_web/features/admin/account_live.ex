defmodule EdenflowersWeb.Admin.AccountLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  require Logger

  alias EdenflowersWeb.Admin.PushSubscriptions
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
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
              {user_initials(@current_user)}
            </span>
            <div class="min-w-0">
              <h2 class="text-base-content truncate text-lg font-semibold">
                {display_name(@current_user)}
              </h2>
              <p
                :if={display_name(@current_user) != user_email(@current_user)}
                class="text-base-content/65 truncate text-sm"
              >
                {user_email(@current_user)}
              </p>
            </div>
          </div>

          <dl class="divide-base-content/8 divide-y">
            <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
              <dt id="avatar-label" class="text-base-content/65 text-sm sm:pt-1.5">{~t"Picture"}</dt>
              <dd>
                <form id="avatar-form" phx-change="validate_avatar" class="grid gap-2">
                  <div class="flex items-center gap-2">
                    <.live_file_input
                      upload={@uploads.avatar}
                      class="file-input min-w-0 flex-1 sm:max-w-xs"
                      aria-labelledby="avatar-label"
                      aria-describedby="avatar-help"
                      aria-invalid={to_string(avatar_errors(@uploads.avatar) != [])}
                    />
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
                    <span :if={avatar_errors(@uploads.avatar) == []} class="text-base-content/65">
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
              <dt class="text-base-content/65 text-sm sm:pt-1.5">{~t"Language"}</dt>
              <dd>
                <Layouts.locale_picker id="admin-locale-picker" current_path={@current_path} class="w-full sm:max-w-xs">
                  <span class="select w-full">{current_language()}</span>
                </Layouts.locale_picker>
              </dd>
            </div>
            <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
              <dt class="text-base-content/65 text-sm">{~t"Access"}</dt>
              <dd class="text-base-content text-sm">{~t"Admin"}</dd>
            </div>
          </dl>

          <div class="border-base-content/12 mt-5 border-t pt-5">
            <.button href={~p"/sign-out"} method="delete" variant="secondary" size="sm">
              <.icon name="hero-arrow-right-start-on-rectangle" class="h-4 w-4" />
              {~t"Sign out"}
            </.button>
          </div>
        </section>

        <.device_notifications :if={@vapid_public_key} vapid_public_key={@vapid_public_key} />
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate_avatar", _params, socket), do: {:noreply, socket}

  def handle_event("push_subscribed", params, socket),
    do: {:reply, PushSubscriptions.subscribe(params, socket.assigns.current_user), socket}

  def handle_event("push_unsubscribed", params, socket),
    do: {:reply, PushSubscriptions.unsubscribe(params, socket.assigns.current_user), socket}

  def handle_event("remove_avatar", _params, socket) do
    user = socket.assigns.current_user

    case Ash.update(user, %{}, action: :remove_avatar, actor: user) do
      {:ok, _user} ->
        {:noreply, redirect(socket, to: ~p"/admin/account")}

      {:error, error} ->
        Logger.error("Profile picture of user #{user.id} not removed: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"Could not remove the profile picture.")}
    end
  end

  defp handle_avatar_progress(:avatar, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_avatar_progress(:avatar, entry, socket) do
    user = socket.assigns.current_user

    # Content type comes from the extension, which allow_upload has already
    # checked against the accept list; the client-reported type is untrusted.
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        params = %{avatar: File.read!(path), avatar_content_type: MIME.from_path(entry.client_name)}
        {:ok, Ash.update(user, params, action: :update_avatar, actor: user)}
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

  attr :vapid_public_key, :string, required: true

  # Per device, so it sits apart from the account details. The PushToggle hook
  # sets data-state from the browser; each help line shows for its states.
  defp device_notifications(assigns) do
    ~H"""
    <section
      id="device-notifications"
      phx-hook="PushToggle"
      phx-update="ignore"
      data-state="checking"
      data-vapid-public-key={@vapid_public_key}
      class="admin-card group mt-6 p-4 sm:p-5"
    >
      <h2 class="text-base-content mb-4 text-base font-semibold">{~t"This device"}</h2>
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <label for="push-toggle" class="text-base-content text-sm font-medium">
            {~t"New order notifications"}
          </label>
          <p id="push-toggle-help" class="mt-0.5 text-sm" aria-live="polite">
            <span class="text-base-content/65 hidden group-data-[state=checking]:inline group-data-[state=off]:inline group-data-[state=on]:inline">
              {~t"Shown on this device only."}
            </span>
            <span class="text-base-content/65 hidden group-data-[state=unsupported]:inline">
              {~t"Add Eden Admin to your home screen to get notifications."}
            </span>
            <span class="text-base-content/65 hidden group-data-[state=denied]:inline">
              {~t"Notifications are blocked. Allow them for Eden Admin in your phone's Settings."}
            </span>
            <span class="text-error hidden group-data-[state=error]:inline">
              {~t"Couldn't turn on notifications. Try again."}
            </span>
          </p>
        </div>
        <input
          id="push-toggle"
          type="checkbox"
          role="switch"
          disabled
          aria-describedby="push-toggle-help"
          class="toggle toggle-primary mt-0.5 shrink-0 group-data-[state=unsupported]:hidden"
        />
      </div>
    </section>
    """
  end

  defp avatar_errors(upload),
    do: upload_errors(upload) ++ Enum.flat_map(upload.entries, &upload_errors(upload, &1))

  defp avatar_error(:too_large), do: ~t"The picture must be under 2 MB."
  defp avatar_error(:not_accepted), do: ~t"Use a JPG, PNG or WebP image."
  defp avatar_error(_), do: ~t"Could not upload the picture."

  defp current_language do
    Localize.get_locale().language
    |> Localize.Language.display_name!(fallback: true)
    |> String.capitalize()
  end

  defp display_name(user) do
    case Map.get(user, :name) do
      name when is_binary(name) ->
        name = String.trim(name)
        if name == "", do: user_email(user), else: name

      _ ->
        user_email(user)
    end
  end

  defp user_email(user), do: user |> Map.get(:email) |> to_string()

  defp user_initials(user) do
    case Map.get(user, :initials) do
      initials when is_binary(initials) ->
        initials = String.trim(initials)
        if initials == "", do: fallback_initial(user), else: initials

      _ ->
        fallback_initial(user)
    end
  end

  defp fallback_initial(user),
    do: user |> user_email() |> String.first() |> Kernel.||("A") |> String.upcase()
end

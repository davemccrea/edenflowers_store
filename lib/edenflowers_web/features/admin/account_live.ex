defmodule EdenflowersWeb.Admin.AccountLive do
  @moduledoc """
  Admin account settings for avatar, back office colour and browser push notifications.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  require Logger

  import EdenflowersWeb.Admin.Components

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
              <dt id="avatar-label" class="text-base-content/75 text-sm sm:pt-1.5">{~t"Picture"}</dt>
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
              <dt class="text-base-content/75 text-sm sm:pt-1.5">{~t"Language"}</dt>
              <dd>
                <Layouts.locale_picker id="admin-locale-picker" current_path={@current_path} class="w-full sm:max-w-xs">
                  <span class="select w-full">{current_language()}</span>
                </Layouts.locale_picker>
              </dd>
            </div>
            <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
              <dt class="text-base-content/75 text-sm sm:pt-1.5">{~t"Colour"}</dt>
              <dd><.appearance_picker user={@current_user} /></dd>
            </div>
            <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
              <dt class="text-base-content/75 text-sm">{~t"Access"}</dt>
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

  def handle_event("update_appearance", params, socket) do
    user = socket.assigns.current_user
    attrs = Map.take(params, ["admin_hue", "admin_chroma", "admin_lightness", "admin_grain"])

    case Edenflowers.Accounts.update_admin_appearance(user, attrs, actor: user) do
      {:ok, user} ->
        {:noreply, assign(socket, :current_user, user)}

      {:error, error} ->
        Logger.error("Admin appearance of user #{user.id} not saved: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"Could not save the appearance.")}
    end
  end

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

  attr :user, :map, required: true

  # Modelled on Arc's theme picker. The field picks hue (across) and lightness
  # (down), the wave slider the colour's intensity and the dial the grain. The
  # hook previews each change on body, where the admin's colour lives (see
  # Layouts.admin_appearance_style/1), and saves when a drag or key press ends.
  # Both sliders are real range inputs under their drawings, so keyboards and
  # screen readers get native controls; the field's handle is an ARIA slider.
  defp appearance_picker(assigns) do
    ~H"""
    <button
      type="button"
      popovertarget="appearance-picker"
      class="admin-picker-trigger border-base-content/12 flex items-center gap-2.5 border py-1.5 pr-3 pl-1.5 text-sm transition-colors hover:bg-base-200"
    >
      <span class="admin-picker-trigger-swatch admin-chrome h-7 w-7 shrink-0 rounded-full" />
      {~t"Change colour"}
    </button>
    <div>
      <div
        id="appearance-picker"
        popover
        phx-hook=".AppearancePicker"
        phx-update="ignore"
        aria-label={~t"Colour"}
        role="dialog"
        data-hue={@user.admin_hue}
        data-chroma={@user.admin_chroma}
        data-lightness={@user.admin_lightness}
        data-grain={@user.admin_grain}
        class="admin-chrome admin-picker-popover text-forest-content w-[22rem] max-w-[calc(100vw-2rem)] select-none overflow-hidden rounded-3xl"
      >
        <div data-field class="admin-picker-field aspect-square relative m-3 cursor-crosshair touch-none rounded-2xl">
          <div
            data-handle
            role="slider"
            tabindex="0"
            aria-label={~t"Colour"}
            aria-valuemin="0"
            aria-valuemax="360"
            class="admin-picker-handle border-[5px] shadow-[0_4px_14px_rgb(0_0_0/0.35)] absolute h-12 w-12 -translate-x-1/2 -translate-y-1/2 rounded-full border-white focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-white"
          />
        </div>

        <div class="flex items-center justify-center gap-2.5 px-3 py-3">
          <button
            :for={{label, hue, chroma, lightness} <- presets()}
            type="button"
            data-preset
            data-hue={hue}
            data-chroma={chroma}
            data-lightness={lightness}
            aria-label={label}
            title={label}
            style={"--h: #{hue}; --c: #{chroma}; --l: #{lightness}"}
            class="admin-swatch touch-target ring-white/25 h-8 w-8 shrink-0 rounded-full ring-1 transition-transform hover:scale-110 active:scale-95"
          />
        </div>

        <div class="flex items-center gap-4 px-4 pt-1 pb-5">
          <div class="relative h-14 min-w-0 flex-1">
            <svg data-wave class="absolute inset-0 h-full w-full overflow-visible" aria-hidden="true">
              <line x1="0" x2="100%" y1="50%" y2="50%" class="stroke-white/15" stroke-width="14" stroke-linecap="round" />
              <path fill="none" class="stroke-white/70" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
            <span
              data-wave-thumb
              class="shadow-[0_4px_14px_rgb(0_0_0/0.3)] pointer-events-none absolute top-1/2 h-14 w-7 -translate-x-1/2 -translate-y-1/2 rounded-full bg-white"
            />
            <input
              data-chroma-input
              type="range"
              min="0"
              max="140"
              aria-label={~t"Colour intensity"}
              class="absolute inset-0 h-full w-full cursor-ew-resize touch-pan-y opacity-0"
            />
          </div>

          <div class="relative h-20 w-20 shrink-0">
            <span
              :for={i <- 0..23}
              data-dial-dot={i}
              class="bg-white/25 -mt-[3px] -ml-[3px] absolute top-1/2 left-1/2 h-1.5 w-1.5 rounded-full data-[lit]:bg-white/85"
              style={"transform: rotate(#{-135 + i * 270 / 23}deg) translateY(-2.3rem)"}
            />
            <span class="admin-picker-knob shadow-[inset_0_1px_2px_rgb(255_255_255/0.2),0_3px_8px_rgb(0_0_0/0.35)] absolute inset-3 rounded-full">
              <span data-dial-mark class="absolute top-1.5 left-1/2 h-3 w-1 -translate-x-1/2 rounded-full bg-white" />
            </span>
            <input
              data-grain-input
              type="range"
              min="0"
              max="100"
              aria-label={~t"Sidebar grain"}
              class="absolute inset-0 h-full w-full cursor-ew-resize touch-pan-y opacity-0"
            />
          </div>
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AppearancePicker">
      const HUE_MAX = 360;
      const L_MIN = 18;
      const L_MAX = 36;

      const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

      /**
       * The account page's colour picker. Keeps hue, chroma, lightness and grain,
       * draws them (handle, wave, dial), previews them on body's --admin-*
       * properties and pushes `update_appearance` once a change settles.
       */
      export default {
        mounted() {
          const data = this.el.dataset;
          this.state = {
            hue: Number(data.hue),
            chroma: Number(data.chroma),
            lightness: Number(data.lightness),
            grain: Number(data.grain),
          };

          this.field = this.el.querySelector("[data-field]");
          this.handle = this.el.querySelector("[data-handle]");
          this.chromaInput = this.el.querySelector("[data-chroma-input]");
          this.grainInput = this.el.querySelector("[data-grain-input]");
          this.wavePath = this.el.querySelector("[data-wave] path");
          this.waveThumb = this.el.querySelector("[data-wave-thumb]");
          this.dialDots = [...this.el.querySelectorAll("[data-dial-dot]")];
          this.dialMark = this.el.querySelector("[data-dial-mark]").parentElement;

          this.field.addEventListener("pointerdown", (event) => {
            this.field.setPointerCapture(event.pointerId);
            this.pickAt(event);
            this.handle.focus({ preventScroll: true });
          });
          this.field.addEventListener("pointermove", (event) => {
            if (this.field.hasPointerCapture(event.pointerId)) this.pickAt(event);
          });
          this.field.addEventListener("pointerup", () => this.save());

          this.handle.addEventListener("keydown", (event) => {
            const step = event.shiftKey ? 10 : 2;
            const moves = {
              ArrowLeft: { hue: -step },
              ArrowRight: { hue: step },
              ArrowUp: { lightness: 1 },
              ArrowDown: { lightness: -1 },
            };
            const move = moves[event.key];
            if (!move) return;
            event.preventDefault();
            this.set({
              hue: (this.state.hue + (move.hue || 0) + HUE_MAX) % HUE_MAX,
              lightness: clamp(
                this.state.lightness + (move.lightness || 0),
                L_MIN,
                L_MAX,
              ),
            });
          });
          this.handle.addEventListener("keyup", (event) => {
            if (event.key.startsWith("Arrow")) this.save();
          });

          this.chromaInput.addEventListener("input", () =>
            this.set({ chroma: Number(this.chromaInput.value) }),
          );
          this.grainInput.addEventListener("input", () =>
            this.set({ grain: Number(this.grainInput.value) }),
          );
          this.chromaInput.addEventListener("change", () => this.save());
          this.grainInput.addEventListener("change", () => this.save());

          this.el.querySelectorAll("[data-preset]").forEach((preset) => {
            preset.addEventListener("click", () => {
              this.set({
                hue: Number(preset.dataset.hue),
                chroma: Number(preset.dataset.chroma),
                lightness: Number(preset.dataset.lightness),
              });
              this.save();
            });
          });

          this.resizeObserver = new ResizeObserver(() => this.draw());
          this.resizeObserver.observe(this.el);
          this.draw();
        },

        destroyed() {
          this.resizeObserver.disconnect();
        },

        pickAt(event) {
          const box = this.field.getBoundingClientRect();
          const x = clamp((event.clientX - box.left) / box.width, 0, 1);
          const y = clamp((event.clientY - box.top) / box.height, 0, 1);
          this.set({
            hue: Math.round(x * (HUE_MAX - 1)),
            lightness: Math.round(L_MAX - y * (L_MAX - L_MIN)),
          });
        },

        set(changes) {
          Object.assign(this.state, changes);
          const style = document.body.style;
          style.setProperty("--admin-hue", this.state.hue);
          style.setProperty("--admin-chroma", this.state.chroma);
          style.setProperty("--admin-lightness", this.state.lightness);
          style.setProperty("--admin-grain", this.state.grain);
          this.draw();
        },

        save() {
          clearTimeout(this.saveTimer);
          this.saveTimer = setTimeout(() => {
            this.pushEvent("update_appearance", {
              admin_hue: this.state.hue,
              admin_chroma: this.state.chroma,
              admin_lightness: this.state.lightness,
              admin_grain: this.state.grain,
            });
          }, 250);
        },

        draw() {
          const { hue, chroma, lightness, grain } = this.state;

          this.handle.style.left = `${(hue / (HUE_MAX - 1)) * 100}%`;
          this.handle.style.top = `${((L_MAX - lightness) / (L_MAX - L_MIN)) * 100}%`;
          this.handle.setAttribute("aria-valuenow", hue);
          this.handle.setAttribute("aria-valuetext", `${hue}°, ${lightness}%`);

          // The wave runs up to the thumb and grows with the intensity, as Arc's does.
          this.chromaInput.value = chroma;
          const wave = this.wavePath.ownerSVGElement.getBoundingClientRect();
          const end = (chroma / 140) * wave.width;
          const middle = wave.height / 2;
          const amplitude = 2 + (chroma / 140) * (middle - 6);
          const points = [];
          for (let x = 0; x <= end; x += 2) {
            points.push(
              `${x === 0 ? "M" : "L"}${x},${middle + Math.sin(x / 7) * amplitude}`,
            );
          }
          this.wavePath.setAttribute("d", points.join(" "));
          this.waveThumb.style.left = `clamp(0.875rem, ${(chroma / 140) * 100}%, calc(100% - 0.875rem))`;

          this.grainInput.value = grain;
          const lit = Math.round((grain / 100) * (this.dialDots.length - 1));
          this.dialDots.forEach((dot, index) =>
            dot.toggleAttribute("data-lit", index <= lit),
          );
          this.dialMark.style.transform = `rotate(${-135 + (grain / 100) * 270}deg)`;
        },
      };
    </script>
    """
  end

  # Starting points under the field: label, hue, chroma, lightness.
  defp presets do
    [
      {~t"Forest", 152, 50, 26},
      {~t"Sage", 140, 25, 32},
      {~t"Teal", 200, 55, 26},
      {~t"Ink", 262, 70, 24},
      {~t"Plum", 325, 70, 26},
      {~t"Berry", 8, 85, 26},
      {~t"Terracotta", 40, 80, 28},
      {~t"Charcoal", 75, 8, 24}
    ]
  end

  attr :vapid_public_key, :string, required: true

  # Per device, so it sits apart from the account details. The PushToggle hook
  # sets data-state from the browser; each help line shows for its states.
  defp device_notifications(assigns) do
    ~H"""
    <section
      id="device-notifications"
      phx-hook=".PushToggle"
      phx-update="ignore"
      data-state="checking"
      data-vapid-public-key={@vapid_public_key}
      class="admin-card group mt-6 p-4 sm:p-5"
    >
      <h2 class="text-base-content mb-4 text-base font-semibold">{~t"This device"}</h2>
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <label for="push-toggle" class="text-base-content text-sm font-semibold">
            {~t"New order notifications"}
          </label>
          <p id="push-toggle-help" class="mt-0.5 text-sm" aria-live="polite">
            <span class="text-base-content/75 hidden group-data-[state=checking]:inline group-data-[state=off]:inline group-data-[state=on]:inline">
              {~t"Shown on this device only."}
            </span>
            <span class="text-base-content/75 hidden group-data-[state=unsupported]:inline">
              {~t"Add Eden Admin to your home screen to get notifications."}
            </span>
            <span class="text-base-content/75 hidden group-data-[state=denied]:inline">
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
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PushToggle">
      import {
        currentSubscription,
        pushSupported,
        resyncSubscription,
        subscribeDevice,
        unsubscribeDevice,
      } from "@/js/push";

      /**
       * The account page's "New order notifications" switch for this device. Its
       * state lives in the browser, so the hook reads it and sets `data-state`
       * (checking, on, off, denied, unsupported, error), which picks the help text.
       * The element is phx-update="ignore", so patches leave the switch alone.
       */
      export default {
        async mounted() {
          this.input = /** @type {HTMLInputElement} */ (
            this.el.querySelector("input[role=switch]")
          );
          this.input.addEventListener("change", () => this.onChange());

          if (!pushSupported()) return this.setState("unsupported");
          if (Notification.permission === "denied") return this.setState("denied");

          const subscription = await resyncSubscription(this);
          this.setState(subscription ? "on" : "off");
        },

        async onChange() {
          this.input.disabled = true;

          if (this.input.checked) {
            this.setState(
              await subscribeDevice(this, this.el.dataset.vapidPublicKey),
            );
          } else {
            await unsubscribeDevice(this).catch(() => {});
            const subscription = await currentSubscription().catch(() => null);
            this.setState(subscription ? "on" : "off");
          }
        },

        /** @param {string} state */
        setState(state) {
          this.js().setAttribute(this.el, "data-state", state);
          this.input.checked = state === "on";
          this.input.disabled = !["on", "off", "error"].includes(state);
        },
      };
    </script>
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
end

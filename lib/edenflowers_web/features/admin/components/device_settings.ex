defmodule EdenflowersWeb.Admin.DeviceSettings do
  @moduledoc """
  The account page's "This device" card: the admin's language and new order
  notifications, which both belong to the browser rather than the account.
  """
  use EdenflowersWeb, {:html, gettext_domain: "admin"}

  alias EdenflowersWeb.Layouts

  attr :current_path, :string, required: true
  attr :vapid_public_key, :string, default: nil

  # Language is kept in the session and notifications are subscribed per
  # browser, so both sit apart from the account details. The PushToggle hook
  # sets data-state from the browser; each help line shows for its states.
  def device_settings(assigns) do
    ~H"""
    <section class="admin-card mt-6 p-4 sm:p-5">
      <h2 class="text-base-content mb-1 text-base font-semibold">{~t"This device"}</h2>
      <dl class="divide-base-content/12 divide-y">
        <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
          <dt class="text-base-content/75 text-sm sm:pt-1.5">{~t"Language"}</dt>
          <dd>
            <Layouts.locale_picker admin? id="admin-locale-picker" current_path={@current_path} class="w-full sm:max-w-xs">
              <span class="select w-full">{current_language()}</span>
            </Layouts.locale_picker>
          </dd>
        </div>
      </dl>
      <div
        :if={@vapid_public_key}
        id="device-notifications"
        phx-hook=".PushToggle"
        phx-update="ignore"
        data-state="checking"
        data-vapid-public-key={@vapid_public_key}
        class="border-base-content/12 group flex items-start justify-between gap-4 border-t pt-3"
      >
        <div class="min-w-0">
          <label for="push-toggle" class="text-base-content text-sm font-semibold">
            {~t"New order and booking notifications"}
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
       * The account page's "New order and booking notifications" switch for this device. Its
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

  defp current_language do
    Localize.get_locale().language
    |> Localize.Language.display_name!(fallback: true)
    |> String.capitalize()
  end
end

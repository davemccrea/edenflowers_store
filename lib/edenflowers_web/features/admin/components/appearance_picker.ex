defmodule EdenflowersWeb.Admin.AppearancePicker do
  @moduledoc """
  The account page's back office colour picker. It saves through the page's
  `update_appearance` event.
  """
  use EdenflowersWeb, {:html, gettext_domain: "admin"}

  attr :user, :map, required: true

  # Modelled on Arc's theme picker. The field picks hue (across) and lightness
  # (down), the wave slider the colour's intensity and the dial the grain. The
  # hook previews each change on body, where the admin's colour lives (see
  # Layouts.admin_appearance_style/1), and saves when a drag or key press ends.
  # Both sliders are real range inputs under their drawings, so keyboards and
  # screen readers get native controls; the field's handle is an ARIA slider.
  def appearance_picker(assigns) do
    assigns = assign(assigns, :limits, limits())

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
        data-hue-max={@limits.hue.max}
        data-chroma-max={@limits.chroma.max}
        data-lightness-min={@limits.lightness.min}
        data-lightness-max={@limits.lightness.max}
        class="admin-chrome admin-picker-popover text-forest-content w-[22rem] max-w-[calc(100vw-2rem)] select-none overflow-hidden rounded-3xl"
      >
        <div data-field class="admin-picker-field aspect-square relative m-3 cursor-crosshair touch-none rounded-2xl">
          <div
            data-handle
            role="slider"
            tabindex="0"
            aria-label={~t"Colour"}
            aria-valuemin="0"
            aria-valuemax={@limits.hue.max}
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
              max={@limits.chroma.max}
              step="any"
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
              max={@limits.grain.max}
              step="any"
              aria-label={~t"Sidebar grain"}
              class="absolute inset-0 h-full w-full cursor-ew-resize touch-pan-y opacity-0"
            />
          </div>
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AppearancePicker">
      /**
       * Loads the colour picker (assets/js/appearance_picker.js) only when it
       * mounts, so no other page downloads it, and mixes its methods in.
       */
      export default {
        async mounted() {
          const { default: picker } = await import("@/js/appearance_picker");
          if (this.gone) return;
          Object.assign(this, picker);
          this.mount();
        },

        destroyed() {
          this.gone = true;
          this.destroy?.();
        },
      };
    </script>
    """
  end

  # The picker's ranges are the User attributes' constraints, so it can't offer
  # a colour the update_admin_appearance action would reject.
  defp limits do
    Map.new(
      [hue: :admin_hue, chroma: :admin_chroma, lightness: :admin_lightness, grain: :admin_grain],
      fn {key, attribute} ->
        constraints = Ash.Resource.Info.attribute(Edenflowers.Accounts.User, attribute).constraints
        {key, %{min: constraints[:min], max: constraints[:max]}}
      end
    )
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
end

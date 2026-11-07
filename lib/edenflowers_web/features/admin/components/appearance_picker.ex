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
              aria-label={~t"Sidebar grain"}
              class="absolute inset-0 h-full w-full cursor-ew-resize touch-pan-y opacity-0"
            />
          </div>
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AppearancePicker">
      const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

      /**
       * The account page's colour picker. Keeps hue, chroma, lightness and grain,
       * draws them (handle, wave, dial), previews them on body's --admin-*
       * properties and pushes `update_appearance` once a change settles.
       */
      export default {
        mounted() {
          const data = this.el.dataset;
          this.hueMax = Number(data.hueMax);
          this.chromaMax = Number(data.chromaMax);
          this.lightnessMin = Number(data.lightnessMin);
          this.lightnessMax = Number(data.lightnessMax);
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
              hue: (this.state.hue + (move.hue || 0) + this.hueMax) % this.hueMax,
              lightness: clamp(
                this.state.lightness + (move.lightness || 0),
                this.lightnessMin,
                this.lightnessMax,
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
            hue: Math.round(x * (this.hueMax - 1)),
            lightness: Math.round(
              this.lightnessMax - y * (this.lightnessMax - this.lightnessMin),
            ),
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
          const { hueMax, chromaMax, lightnessMin, lightnessMax } = this;

          this.handle.style.left = `${(hue / (hueMax - 1)) * 100}%`;
          this.handle.style.top = `${((lightnessMax - lightness) / (lightnessMax - lightnessMin)) * 100}%`;
          this.handle.setAttribute("aria-valuenow", hue);
          this.handle.setAttribute("aria-valuetext", `${hue}°, ${lightness}%`);

          // The wave runs up to the thumb and grows with the intensity, as Arc's does.
          this.chromaInput.value = chroma;
          const wave = this.wavePath.ownerSVGElement.getBoundingClientRect();
          const end = (chroma / chromaMax) * wave.width;
          const middle = wave.height / 2;
          const amplitude = 2 + (chroma / chromaMax) * (middle - 6);
          const points = [];
          for (let x = 0; x <= end; x += 2) {
            points.push(
              `${x === 0 ? "M" : "L"}${x},${middle + Math.sin(x / 7) * amplitude}`,
            );
          }
          this.wavePath.setAttribute("d", points.join(" "));
          this.waveThumb.style.left = `clamp(0.875rem, ${(chroma / chromaMax) * 100}%, calc(100% - 0.875rem))`;

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

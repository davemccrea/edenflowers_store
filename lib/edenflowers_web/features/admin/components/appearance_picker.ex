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
      const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

      const DIAL_DETENTS = 23;
      const WAVE_DETENTS = 14;

      /**
       * The account page's colour picker. Keeps hue, chroma, lightness and grain
       * as exact numbers while they move, so the handle glides with the pointer,
       * and rounds them only to save. Draws them (handle, wave, dial) and previews
       * them on body's --admin-* properties once per frame, ticks like Arc's
       * detents as the dial and wave pass a step, and pushes `update_appearance`
       * once a change settles.
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
          this.dialKnob = this.el.querySelector("[data-dial-mark]").parentElement;
          this.haptic = this.createHaptic();

          this.field.addEventListener("pointerdown", (event) =>
            this.startFieldDrag(event),
          );
          this.field.addEventListener("pointermove", (event) => {
            if (this.field.hasPointerCapture(event.pointerId)) this.pickAt(event);
          });
          this.field.addEventListener("pointerup", () => this.endDrag());
          this.field.addEventListener("pointercancel", () => this.endDrag());

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

          for (const input of [this.chromaInput, this.grainInput]) {
            input.addEventListener("pointerdown", () =>
              this.el.toggleAttribute("data-dragging", true),
            );
            input.addEventListener("pointerup", () => this.endDrag());
            input.addEventListener("change", () => this.save());
          }
          this.chromaInput.addEventListener("input", () =>
            this.set({ chroma: Number(this.chromaInput.value) }),
          );
          this.grainInput.addEventListener("input", () =>
            this.set({ grain: Number(this.grainInput.value) }),
          );

          this.el.querySelectorAll("[data-preset]").forEach((preset) => {
            preset.addEventListener("click", () => {
              this.tick(preset);
              this.set({
                hue: Number(preset.dataset.hue),
                chroma: Number(preset.dataset.chroma),
                lightness: Number(preset.dataset.lightness),
              });
              this.save();
            });
          });

          this.detents = this.currentDetents();
          this.resizeObserver = new ResizeObserver(() => this.draw());
          this.resizeObserver.observe(this.el);
          this.draw();
        },

        destroyed() {
          this.resizeObserver.disconnect();
          cancelAnimationFrame(this.frame);
          this.haptic?.label.remove();
        },

        // Grabbing the handle keeps the point under the finger where it is, as
        // Arc's does. Pressing elsewhere in the field glides the handle there.
        startFieldDrag(event) {
          this.field.setPointerCapture(event.pointerId);
          const handleBox = this.handle.getBoundingClientRect();
          const onHandle = event.target === this.handle;
          this.grabOffset = onHandle
            ? {
                x: event.clientX - (handleBox.left + handleBox.width / 2),
                y: event.clientY - (handleBox.top + handleBox.height / 2),
              }
            : { x: 0, y: 0 };
          this.el.toggleAttribute("data-gliding", !onHandle);
          this.el.toggleAttribute("data-dragging", true);
          this.tick();
          this.pickAt(event);
          this.handle.focus({ preventScroll: true });
          // The glide only covers the jump to the pressed point; the drag after it follows directly.
          setTimeout(() => this.el.removeAttribute("data-gliding"), 180);
        },

        endDrag() {
          if (!this.el.hasAttribute("data-dragging")) return;
          this.el.removeAttribute("data-dragging");
          this.save();
        },

        pickAt(event) {
          const box = this.field.getBoundingClientRect();
          const x = clamp(
            (event.clientX - this.grabOffset.x - box.left) / box.width,
            0,
            1,
          );
          const y = clamp(
            (event.clientY - this.grabOffset.y - box.top) / box.height,
            0,
            1,
          );
          this.set({
            hue: x * (this.hueMax - 1),
            lightness:
              this.lightnessMax - y * (this.lightnessMax - this.lightnessMin),
          });
        },

        set(changes) {
          Object.assign(this.state, changes);

          const detents = this.currentDetents();
          if (detents.dial !== this.detents.dial) this.tick(this.dialKnob);
          if (detents.wave !== this.detents.wave) this.tick(this.waveThumb);
          this.detents = detents;

          // Restyling body recolours the whole page, so do it once a frame at most.
          cancelAnimationFrame(this.frame);
          this.frame = requestAnimationFrame(() => {
            const style = document.body.style;
            style.setProperty("--admin-hue", this.state.hue);
            style.setProperty("--admin-chroma", this.state.chroma);
            style.setProperty("--admin-lightness", this.state.lightness);
            style.setProperty("--admin-grain", this.state.grain);
            this.draw();
          });
        },

        currentDetents() {
          return {
            dial: Math.round((this.state.grain / 100) * DIAL_DETENTS),
            wave: Math.round((this.state.chroma / this.chromaMax) * WAVE_DETENTS),
          };
        },

        save() {
          clearTimeout(this.saveTimer);
          this.saveTimer = setTimeout(() => {
            this.pushEvent("update_appearance", {
              admin_hue: Math.round(this.state.hue),
              admin_chroma: Math.round(this.state.chroma),
              admin_lightness: Math.round(this.state.lightness),
              admin_grain: Math.round(this.state.grain),
            });
          }, 250);
        },

        // iOS Safari has no vibrate(), but since iOS 18 toggling a native switch
        // gives a light haptic tick, so a hidden one stands in. Android vibrates.
        createHaptic() {
          const label = document.createElement("label");
          label.setAttribute("aria-hidden", "true");
          label.style.cssText =
            "position:fixed;width:1px;height:1px;opacity:0;pointer-events:none;overflow:hidden";
          const input = document.createElement("input");
          input.type = "checkbox";
          input.setAttribute("switch", "");
          input.tabIndex = -1;
          label.append(input);
          document.body.append(label);
          return { label };
        },

        tick(element) {
          const now = performance.now();
          if (now - (this.lastTick || 0) < 40) return;
          this.lastTick = now;

          this.haptic.label.click();
          navigator.vibrate?.(6);

          if (element && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
            element.animate([{ scale: 1 }, { scale: 1.06 }, { scale: 1 }], {
              duration: 140,
              easing: "ease-out",
            });
          }
        },

        draw() {
          const { hue, chroma, lightness, grain } = this.state;
          const { hueMax, chromaMax, lightnessMin, lightnessMax } = this;

          this.handle.style.left = `${(hue / (hueMax - 1)) * 100}%`;
          this.handle.style.top = `${((lightnessMax - lightness) / (lightnessMax - lightnessMin)) * 100}%`;
          this.handle.setAttribute("aria-valuenow", Math.round(hue));
          this.handle.setAttribute(
            "aria-valuetext",
            `${Math.round(hue)}°, ${Math.round(lightness)}%`,
          );

          // The wave runs up to the thumb and grows with the intensity, as Arc's
          // does. Its phase is anchored at the thumb, so the stretch beside the
          // thumb stays put and the wave unrolls from the left as it moves.
          if (document.activeElement !== this.chromaInput)
            this.chromaInput.value = chroma;
          const wave = this.wavePath.ownerSVGElement.getBoundingClientRect();
          const end = (chroma / chromaMax) * wave.width;
          const middle = wave.height / 2;
          const amplitude = 2 + (chroma / chromaMax) * (middle - 6);
          const points = [];
          for (let x = 0; x <= end; x += 1.5) {
            points.push(
              `${x === 0 ? "M" : "L"}${x.toFixed(1)},${(middle + Math.sin((end - x) / 7) * amplitude).toFixed(2)}`,
            );
          }
          this.wavePath.setAttribute("d", points.join(" "));
          this.waveThumb.style.left = `clamp(0.875rem, ${(chroma / chromaMax) * 100}%, calc(100% - 0.875rem))`;

          if (document.activeElement !== this.grainInput)
            this.grainInput.value = grain;
          const lit = Math.round((grain / 100) * (this.dialDots.length - 1));
          this.dialDots.forEach((dot, index) =>
            dot.toggleAttribute("data-lit", index <= lit),
          );
          this.dialKnob.style.transform = `rotate(${-135 + (grain / 100) * 270}deg)`;
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

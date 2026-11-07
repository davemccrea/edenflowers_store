const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

const WAVE_DETENTS = 14;

/**
 * The admin account page's colour picker, loaded only when the picker mounts
 * (see the .AppearancePicker hook in EdenflowersWeb.Admin.AppearancePicker).
 * Its methods are mixed into that hook, so `this` is the hook.
 *
 * It keeps hue, chroma, lightness and grain as exact numbers while they
 * move, so the handle glides with the pointer, and rounds them only to save.
 * Draws them (handle, wave, dial), previews them on body's --admin-*
 * properties once per frame, pulses like Arc's detents as the dial and wave
 * pass a step, and pushes `update_appearance` once a change settles.
 */
export default {
  mount() {
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
      const dh = { ArrowLeft: -step, ArrowRight: step }[event.key] ?? 0;
      const dl = { ArrowUp: 1, ArrowDown: -1 }[event.key] ?? 0;
      if (!dh && !dl) return;
      event.preventDefault();
      this.set({
        hue: (this.state.hue + dh + this.hueMax) % this.hueMax,
        lightness: clamp(
          this.state.lightness + dl,
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
        this.pulse(preset);
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

  destroy() {
    this.resizeObserver.disconnect();
    cancelAnimationFrame(this.frame);
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
    if (detents.dial !== this.detents.dial) this.pulse(this.dialKnob, 1.02);
    if (detents.wave !== this.detents.wave) this.pulse(this.waveThumb);
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
      dial: Math.round((this.state.grain / 100) * (this.dialDots.length - 1)),
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

  // A small pulse of the control at each step, like Arc's detents.
  pulse(element, peakScale = 1.06) {
    const now = performance.now();
    if (now - (this.lastPulse || 0) < 40) return;
    this.lastPulse = now;

    if (!matchMedia("(prefers-reduced-motion: reduce)").matches) {
      element.animate([{ scale: 1 }, { scale: peakScale }, { scale: 1 }], {
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

    // The wave stays fixed on the track and runs up to the thumb, growing with
    // the intensity, as Arc's does. While a slider is dragged it owns its value.
    const dragging = this.el.hasAttribute("data-dragging");
    if (!dragging) this.chromaInput.value = chroma;
    const wave = this.wavePath.ownerSVGElement.getBoundingClientRect();
    // The native thumb is styled to the pill's width (admin.css), so the
    // browser maps the pointer the same way: half a thumb in from each end.
    const thumbWidth = this.waveThumb.offsetWidth;
    const end =
      thumbWidth / 2 + (chroma / chromaMax) * (wave.width - thumbWidth);
    const middle = wave.height / 2;
    const amplitude = 2 + (chroma / chromaMax) * 9;
    const points = [];
    for (let x = 0; x <= end; x += 1.5) {
      points.push(
        `${x === 0 ? "M" : "L"}${x.toFixed(1)},${(middle + Math.sin(x / 7) * amplitude).toFixed(2)}`,
      );
    }
    this.wavePath.setAttribute("d", points.join(" "));
    this.waveThumb.style.left = `${end}px`;

    if (!dragging) this.grainInput.value = grain;
    const lit = this.detents.dial;
    this.dialDots.forEach((dot, index) =>
      dot.toggleAttribute("data-lit", index <= lit),
    );
    this.dialKnob.style.transform = `rotate(${-135 + (grain / 100) * 270}deg)`;
  },
};

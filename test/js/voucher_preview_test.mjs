import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const source = readFileSync(
  new URL("../../assets/js/voucher_preview.mjs", import.meta.url),
  "utf8",
).replace("export const VoucherPreview =", "globalThis.VoucherPreview =");

function fixture({
  mobile = true,
  sticky = true,
  fieldTop = 100,
  fieldHeight = 160,
  reducedMotion = false,
  scrollEnd = true,
} = {}) {
  const viewport = Object.assign(new EventTarget(), {
    height: 844,
    offsetTop: 0,
    scale: 1,
  });
  const timers = new Map();
  const frames = new Map();
  let timerId = 0;
  let frameId = 0;
  const attributes = new Set();
  const scrolls = [];
  const behaviors = [];
  const bounds = {
    top: fieldTop,
    bottom: fieldTop + fieldHeight,
    height: fieldHeight,
  };
  const fieldset = { getBoundingClientRect: () => ({ ...bounds }) };
  const field = {
    isConnected: true,
    matches: () => true,
    closest: () => fieldset,
    blur: () => assert.fail("Closing the keyboard must not blur the field"),
    focus: () => assert.fail("Closing the keyboard must not focus a field"),
  };
  const otherControl = { matches: () => false, closest: () => otherControl };
  const body = { matches: () => false, closest: () => null };
  const form = Object.assign(new EventTarget(), {
    contains: (node) => node === field,
  });
  const el = {
    closest: () => form,
    hasAttribute: (name) => attributes.has(name),
    setAttribute: (name) => attributes.add(name),
    removeAttribute: (name) => attributes.delete(name),
    toggleAttribute: (name, enabled) =>
      enabled ? attributes.add(name) : attributes.delete(name),
    getBoundingClientRect: () => ({ top: 0, bottom: 276, height: 276 }),
  };
  const document = Object.assign(new EventTarget(), {
    activeElement: body,
    body,
    documentElement: { scrollHeight: 5000, clientHeight: 844 },
    getElementById: () => ({ offsetHeight: 64 }),
  });
  if (scrollEnd) document.onscrollend = null;
  const window = Object.assign(new EventTarget(), {
    innerWidth: mobile ? 390 : 1440,
    innerHeight: 844,
    scrollY: 1000,
    scrollX: 0,
    visualViewport: viewport,
    matchMedia: (query) => ({
      matches: query.includes("reduced-motion") ? reducedMotion : mobile,
    }),
    scrollBy: ({ top, behavior }) => {
      scrolls.push(top);
      behaviors.push(behavior);
      window.scrollY += top;
      bounds.top -= top;
      bounds.bottom -= top;
    },
    scrollTo: ({ top }) => {
      assert.equal(top, window.scrollY);
    },
  });
  const context = {
    document,
    window,
    setTimeout: (callback) => {
      const id = ++timerId;
      timers.set(id, callback);
      return id;
    },
    clearTimeout: (id) => timers.delete(id),
    requestAnimationFrame: (callback) => {
      const id = ++frameId;
      frames.set(id, callback);
      return id;
    },
    cancelAnimationFrame: (id) => frames.delete(id),
    getComputedStyle: (node, pseudo) => ({
      paddingBottom: "0px",
      height: pseudo ? "32px" : "auto",
      position:
        sticky &&
        !attributes.has("data-keyboard-open") &&
        !attributes.has("data-field-too-tall")
          ? "sticky"
          : "relative",
    }),
  };
  vm.runInNewContext(source, context);
  const hook = Object.assign(context.VoucherPreview, { el, handleEvent() {} });
  hook.mounted();
  document.activeElement = field;
  hook.onFocusIn({ target: field });
  return {
    hook,
    window,
    document,
    viewport,
    field,
    body,
    otherControl,
    scrolls,
    behaviors,
    bounds,
    attributes,
    keyboardOpen: () => attributes.has("data-keyboard-open"),
    resize(height) {
      viewport.height = height;
      viewport.dispatchEvent(new Event("resize"));
    },
    settle() {
      const callbacks = [...frames.values()];
      frames.clear();
      for (const callback of callbacks) callback();
    },
    runTimers() {
      const callbacks = [...timers.values()];
      timers.clear();
      for (const callback of callbacks) callback();
    },
  };
}

test("keeps the edited field including its label and help below the preview, without advancing or changing focus", () => {
  const f = fixture();
  f.resize(504);
  for (let height = 524; height <= 844; height += 20) f.resize(height);
  assert.equal(
    f.keyboardOpen(),
    true,
    "preview restores on the next animation frame",
  );
  assert.deepEqual(f.scrolls, []);
  f.settle();
  assert.equal(f.keyboardOpen(), false);
  assert.deepEqual(f.scrolls, [-224]);
  assert.deepEqual(f.behaviors, ["smooth"]);
  assert.equal(f.attributes.has("data-preview-owns-top"), true);
  assert.equal(f.bounds.top, 324);
  assert.equal(f.document.activeElement, f.field);
  f.hook.destroyed();
});

test("does not scroll when the edited field is already fully visible", () => {
  const f = fixture({ fieldTop: 350 });
  f.resize(504);
  f.resize(844);
  f.settle();
  assert.deepEqual(f.scrolls, []);
  f.hook.destroyed();
});

test("moves only enough to reveal help or errors below the bottom of the viewport", () => {
  const f = fixture({ fieldTop: 700 });
  f.resize(504);
  f.resize(844);
  f.settle();
  assert.deepEqual(f.scrolls, [32]);
  assert.equal(f.bounds.bottom, 828);
  f.hook.destroyed();
});

test("detects dismissal when Safari changes innerHeight too, and the field has blurred", () => {
  const f = fixture();
  f.window.innerHeight = 504;
  f.resize(504);
  assert.equal(f.keyboardOpen(), true);
  f.document.activeElement = f.body;
  f.hook.onPointerDown({ target: f.body });
  f.window.innerHeight = 844;
  f.resize(844);
  f.settle();
  assert.deepEqual(f.scrolls, [-224]);
  assert.equal(f.document.activeElement, f.body);
  f.hook.destroyed();
});

test("Safari Done starts positioning the edited field on blur, before the delayed viewport resize", () => {
  const f = fixture();
  f.resize(504);
  f.settle();
  f.document.activeElement = f.body;
  f.hook.onFocusOut();
  f.runTimers();
  assert.deepEqual(f.scrolls, [-224]);
  assert.deepEqual(f.behaviors, ["smooth"]);
  assert.equal(
    f.keyboardOpen(),
    true,
    "preview stays in flow while keyboard is still visible",
  );
  assert.equal(f.viewport.height, 504, "no resize has been reported yet");
  f.resize(844);
  f.settle();
  f.hook.onScrollEnd();
  f.settle();
  assert.deepEqual(
    f.scrolls,
    [-224],
    "does not start a second scroll after viewport catches up",
  );
  assert.equal(f.keyboardOpen(), false);
  assert.equal(f.document.activeElement, f.body);
  f.hook.destroyed();
});

test("accounts for Safari's visual-viewport pan and repairs a late viewport movement", () => {
  const f = fixture({ fieldTop: 300 });
  f.resize(504);
  f.resize(844);
  f.viewport.offsetTop = 80;
  f.viewport.dispatchEvent(new Event("scroll"));
  f.settle();
  assert.deepEqual(f.scrolls, [-104]);
  f.hook.onScrollEnd();
  f.settle();
  f.viewport.offsetTop = 100;
  f.viewport.dispatchEvent(new Event("scroll"));
  f.settle();
  assert.deepEqual(f.scrolls, [-104, -20]);
  f.hook.destroyed();
});

test("starts on the next frame despite continuing viewport events and does not restart its own smooth scroll", () => {
  const f = fixture();
  f.resize(504);
  f.resize(730);
  f.settle();
  assert.deepEqual(f.scrolls, [-224]);
  for (let height = 734; height <= 844; height += 10) {
    f.resize(height);
    f.document.dispatchEvent(new Event("scroll"));
    f.settle();
  }
  assert.deepEqual(f.scrolls, [-224]);
  assert.deepEqual(f.behaviors, ["smooth"]);
  f.hook.destroyed();
});

test("uses an instant correction for reduced motion", () => {
  const f = fixture({ reducedMotion: true });
  f.resize(504);
  f.resize(844);
  f.settle();
  assert.deepEqual(f.behaviors, ["instant"]);
  f.hook.destroyed();
});

test("older Safari releases the scroll guard after scrolling stops, without delaying the start", () => {
  const f = fixture({ scrollEnd: false });
  f.resize(504);
  f.resize(844);
  f.settle();
  assert.deepEqual(f.behaviors, ["smooth"]);
  assert.equal(f.hook.scrolling, true);
  f.document.dispatchEvent(new Event("scroll"));
  f.runTimers();
  f.settle();
  assert.equal(f.hook.scrolling, false);
  assert.deepEqual(f.scrolls, [-224]);
  f.hook.destroyed();
});

test("lets the preview scroll away when the whole edited field cannot fit beneath it", () => {
  const f = fixture({ fieldHeight: 600 });
  f.resize(504);
  f.resize(844);
  f.settle();
  assert.equal(f.attributes.has("data-field-too-tall"), true);
  assert.deepEqual(f.scrolls, []);
  f.attributes.delete("data-field-too-tall");
  f.hook.updated();
  assert.equal(
    f.attributes.has("data-field-too-tall"),
    true,
    "a LiveView patch must preserve the fallback",
  );
  f.hook.destroyed();
});

test("short screens keep the field clear of the returning site header", () => {
  const f = fixture({ sticky: false, fieldTop: 20 });
  f.resize(504);
  f.resize(844);
  f.settle();
  assert.deepEqual(f.scrolls, [-60]);
  f.hook.destroyed();
});

test("respects a tap on another control instead of returning to the old field", () => {
  const f = fixture();
  f.resize(504);
  f.hook.onPointerDown({ target: f.otherControl });
  f.document.activeElement = f.otherControl;
  f.hook.onFocusIn({ target: f.otherControl });
  f.resize(844);
  f.settle();
  assert.equal(f.keyboardOpen(), false);
  assert.deepEqual(f.scrolls, []);
  f.hook.destroyed();
});

test("does not fight a new scroll gesture after the keyboard has closed", () => {
  const f = fixture({ fieldTop: 350 });
  f.resize(504);
  f.resize(844);
  f.settle();
  f.hook.onPointerDown({ target: f.body });
  f.viewport.offsetTop = 100;
  f.viewport.dispatchEvent(new Event("scroll"));
  f.settle();
  assert.deepEqual(f.scrolls, []);
  f.hook.destroyed();
});

test("desktop resize, pinch zoom, and unmount do not reposition a field", () => {
  for (const mobile of [false, true]) {
    const f = fixture({ mobile });
    if (mobile) f.viewport.scale = 2;
    f.resize(504);
    f.resize(844);
    f.settle();
    assert.deepEqual(f.scrolls, []);
    f.hook.destroyed();
    f.resize(504);
    f.settle();
    assert.equal(f.keyboardOpen(), false);
  }
});

import assert from "node:assert/strict";
import { test } from "node:test";
import faqSection from "../../assets/js/faq_section_toggle.mjs";

const fixture = () => {
  const items = [{ open: false }, { open: false }];
  const classes = new Set();
  const attributes = new Map();
  const button = new EventTarget();
  button.setAttribute = (name, value) => attributes.set(name, value);
  button.parentElement = {
    classList: {
      toggle(name, enabled) {
        if (enabled) classes.add(name);
        else classes.delete(name);
      },
    },
  };
  const section = new EventTarget();
  section.querySelector = (selector) => {
    assert.equal(selector, "[data-faq-section-toggle]");
    return button;
  };
  section.querySelectorAll = (selector) => {
    assert.equal(selector, "details");
    return items;
  };
  const hook = { ...faqSection, el: section };
  hook.mounted();

  return {
    hook,
    items,
    attributes,
    classes,
    click: () => button.dispatchEvent(new Event("click")),
    toggle: () => section.dispatchEvent(new Event("toggle")),
  };
};

test("a heading opens and closes only the answers in its own section", () => {
  const section = fixture();
  const other = fixture();

  section.click();
  assert.ok(section.items.every((item) => item.open));
  assert.ok(other.items.every((item) => !item.open));
  assert.equal(section.attributes.get("aria-expanded"), "true");
  assert.ok(section.classes.has("collapse-open"));

  section.click();
  assert.ok(section.items.every((item) => !item.open));
  assert.equal(section.attributes.get("aria-expanded"), "false");
  assert.ok(!section.classes.has("collapse-open"));
});

test("a partly open section opens the remaining answers", () => {
  const section = fixture();
  section.items[0].open = true;

  section.click();

  assert.ok(section.items.every((item) => item.open));
  assert.equal(section.attributes.get("aria-expanded"), "true");
});

test("individual toggles keep the section chevron and accessible state in sync", () => {
  const section = fixture();
  section.items.forEach((item) => (item.open = true));
  section.toggle();
  assert.equal(section.attributes.get("aria-expanded"), "true");
  assert.ok(section.classes.has("collapse-open"));

  section.items[0].open = false;
  section.toggle();
  assert.equal(section.attributes.get("aria-expanded"), "false");
  assert.ok(!section.classes.has("collapse-open"));
});

test("a patch resynchronizes the heading without changing native open state", () => {
  const section = fixture();
  section.click();
  section.attributes.set("aria-expanded", "false");
  section.classes.clear();

  section.hook.updated();

  assert.ok(section.items.every((item) => item.open));
  assert.equal(section.attributes.get("aria-expanded"), "true");
  assert.ok(section.classes.has("collapse-open"));
});

test("destroying the hook removes both event listeners", () => {
  const section = fixture();
  section.hook.destroyed();
  section.click();
  assert.ok(section.items.every((item) => !item.open));

  section.items.forEach((item) => (item.open = true));
  section.toggle();
  assert.equal(section.attributes.get("aria-expanded"), "false");
});

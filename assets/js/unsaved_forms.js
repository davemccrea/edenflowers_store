// Admin forms marked data-warn-unsaved (holding the warning text) ask before a
// link leaves them with edits. Kept in a WeakSet rather than an attribute, which
// LiveView would strip on the next patch. A save navigates from the server, so
// it never asks; a failed save stays flagged.
const editedForms = new WeakSet();

const warnedForm = (el) =>
  el?.closest?.("form[data-warn-unsaved]") ||
  (el?.form?.matches("[data-warn-unsaved]") ? el.form : null);

const unsavedForm = () =>
  [...document.querySelectorAll("form[data-warn-unsaved]")].find((form) =>
    editedForms.has(form),
  );

document.addEventListener("input", (event) => {
  const form = warnedForm(event.target);
  if (form) editedForms.add(form);
});

// Adding or removing a size, translating and the like change the form on the
// server. A phx-click holding JS commands (copying a code) is client-only.
document.addEventListener("click", (event) => {
  const button = event.target.closest?.('button[type="button"][phx-click]');
  if (button?.getAttribute("phx-click").startsWith("[")) return;
  const form = warnedForm(button);
  if (form) editedForms.add(form);
});

window.addEventListener("phx:before-navigate", (event) => {
  const form = unsavedForm();
  if (!form) return;
  if (confirm(form.dataset.warnUnsaved)) return editedForms.delete(form);

  event.preventDefault();
});

// Only warn when the person leaves. LiveView disconnects before its own reload
// after a failed rejoin, and retries every few seconds if the reload is
// cancelled; dev live reload also reloads on .po and asset changes.
let liveReloading = false;

window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
  reloader.channel.on("assets_change", () => (liveReloading = true));
});

window.addEventListener("beforeunload", (event) => {
  if (liveReloading || !window.liveSocket.isConnected()) return;
  if (unsavedForm()) event.preventDefault();
});

window.addEventListener("phx:admin-form-saved", ({ detail }) => {
  const form = document.getElementById(detail.id);
  if (form) editedForms.delete(form);
});

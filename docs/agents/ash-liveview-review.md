# Reviewing Ash, LiveView and form code

Use this to review a diff, a feature or a set of pages for idiomatic Ash, LiveView and AshPhoenix forms. It builds on the Ash section of `CLAUDE.md`. The `ash-framework` and `phoenix-framework` skills have the API details.

## Steps

1. **Scope.** List every resource, LiveView, component and form in the change, or all the files the user named. For a page, include the action its form submits and the components it renders.
2. **Read.** Follow each form from mount to its action: what builds it, what runs on every change, what runs on submit, and what the page shows that the action also decides.
3. **Apply every rule below to every file in scope.** Grep across the codebase for each rule's smells too, so a pattern found once is checked everywhere. Confirm each finding in context: some matches are deliberate (see *Fine as is*).
4. **Report.** Rank the findings worst first. Each one names the file and line, the rule, the concrete failure (two values that can differ, a render per keystroke, an error Jennie can't place) and the fix that deletes the most code. Then list what looked suspicious but is fine, and why. Say which files only got a grep.

You're done when every rule has been applied to every file in scope and every finding names a concrete failure.

## Rules

### One source per rule (Ash)

A page and an action that answer the same question read the same calculation, so they can't **drift**. Look for:

- `cond`/`case` in a LiveView over a record's fields (dates, usage, state) to decide a status. Fix: a calculation on the resource that the page loads. `Promotion.status`, with `usable?` defined on top of it, is the model.
- Option lists filtered in the page by a setting the action also checks. Fix: a calculation that both the page's options and the action's validation read, like `ShopCalendar.online_voucher_styles`.
- Money arithmetic in a component (refunds, balances, what's left to pay). Fix: call the function the action uses, like `Changes.Cancel.money/2`.

### PubSub (Ash to LiveView)

- A topic name lives in `Edenflowers.Events`, never as a literal string. Resources publish with `Events.<topic>()` from their `pub_sub` block; pages subscribe with `Edenflowers.Events.subscribe/1` or `EdenflowersWeb.Admin.PubSub.subscribe/1`.
- An admin-facing resource publishes to its collection topic (`admin:<collection>`) and, when a detail page shows one record, its record topic (`admin:<collection>:<id>`). Pages showing related records follow their collection topics; the queries still select only the page's records.
- Lists and dashboards refresh automatically. Admin detail/editor pages only warn on external notifications: do not reload records, tables, calculations or forms, and do not schedule a refresh. Own notifications never reload either; successful local actions explicitly reload saved data and rebuild the affected forms together. Use record topics for editors and collection topics for related data, rather than action-name exceptions or payload relevance checks. Subscribe only when `connected?(socket)`, and add a catch-all `handle_info/2`.
- Coalesce bursty list/dashboard refreshes with `EdenflowersWeb.Admin.PubSub.schedule_refresh/3`. Notifications share one pending timer without postponing it. A list table beside an editor may refresh independently, but must not change the editor's saved data or forms.
- Every admin detail/editor page warns on external changes, whether or not the user has typed. `PubSub.mark_stale/3` ignores own writes and sends a flash notification, so scrolled editors still notice. Show `stale_editor_notice` prominently on the page and inside editor drawers, with a confirmed discard-and-reload action. Saving remains available: the shop accepts overwrite risk and can consult PaperTrail. Do not track dirty forms, merge drafts, repair missing forms after notifications or add concurrency locking. Explicit reload replaces the complete page state and discards local input. Keep the editor notice until reload or a successful save, never clear it merely on drawer open/close or validation failure. Creation forms warn about changing saved dependencies when relevant. Customer-facing payment/stock notifications retain their specific live updates.

### Forms (AshPhoenix)

- A form that submits one action is built with `AshPhoenix.Form.for_create`/`for_update`, so errors land on their fields. `to_form(map)` is for UI-only forms.
- To change a param on the server (shuffle, generate a code), use `AshPhoenix.Form.update_params/3`, not `form.params` or `form.source.params` passed back to `validate`.
- Read typed values from the form. Once valid, `form[:field].value` is the cast value (`Date`, integer, atom); while invalid, it's the raw string. Previews read the changeset: `Ash.Changeset.get_attribute(form.source.source, ...)` and `get_argument`. Ash strings already trim and turn `""` into nil, and `Edenflowers.Types.Price` accepts a decimal comma. Look for `Integer.parse`, `Decimal.parse`, `Date.from_iso8601`, `String.trim` or `String.replace(",", ".")` on form values.
- To convert between what the form shows and what the resource stores (a percentage against a rate), use `transform_params`, as `PromotionFormLive.percent_to_rate/3` does.

### LiveView

- Slow work on change (Typst, address lookups) runs in `start_async` and is skipped when the inputs that feed it haven't changed. Store those inputs and compare them, as the gift voucher preview and the order form's delivery quote do.
- A loading state follows the work itself: dim from an assign set when the work starts. `phx-change-loading` fires for every field in the form, including ones that don't feed the work.
- Text inputs in a `phx-change` form have `phx-debounce`.
- What a drawer shows about a record is loaded once when it opens and kept in assigns. Hidden inputs that send server values back and forth are a smell.
- A one-use helper that returns a class string or wraps one call is inlined.

## Fine as is

- `@form.source.type` and `@form.source.data` in a page header, to show the saved record.
- `value={form.source.raw_params[...]}` to echo a decimal comma as Jennie typed it (the invoice payment amount).
- A rule enforced in the action that the page also checks first for a friendlier message, like the fulfillment photo.

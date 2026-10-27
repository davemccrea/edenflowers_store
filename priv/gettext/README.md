# Translating Eden Flowers

English is the source language. Swedish (`sv`) and Finnish (`fi`) translations
live in `<language>/LC_MESSAGES/`. Edit the `.po` files, not the `.pot` templates.
Empty English translations intentionally fall back to the English source text.

## What to translate first

| Catalogue | Audience and content | Priority |
| --- | --- | --- |
| `storefront.po` | Public pages, checkout, sign-in, customer accounts and customer-facing domain messages | Critical |
| `emails.po` | Customer email subjects and bodies, including emails sent by the shop through admin | Critical |
| `receipts.po` | Labels and copy printed in order and course receipt PDFs | Critical |
| `shared.po` | Reusable UI components, formatting, product descriptions and delivery errors used across audiences | Critical |
| `errors.po` | Generic form/validation errors | Critical |
| `admin.po` | Back office, accounting reports, admin-only action errors and notifications to the shop | Can wait |
| `cinder.po` | Admin table library | Can wait |
| `routes.po` | Localised URL segments | Coordinate with a developer; changing these changes URLs |

A message belongs to the audience that **reads it**, not the audience that triggers
it. An order email sent from admin still belongs in `emails.po`.

The same English wording can appear in several catalogues. Translate it in each
catalogue: the audience or context can require different wording. `msgctxt`
distinguishes meanings within a catalogue, such as a cancelled subscription versus
a cancelled order.

Preserve `%{placeholders}` exactly. Plural entries need every `msgstr[n]` form.
Entries marked `fuzzy` need review before their translations are used. Entries
prefixed with `#~` are obsolete: retained translation history, not current work.

## Update and check progress

```sh
mix gettext.extract --merge
mix gettext.stats
mix gettext.extract --check-up-to-date
mix gettext.check
```

The progress report separates critical and deferrable work by language and
catalogue. Missing translations and fuzzy entries are counted separately; obsolete
entries are excluded. English source text counts as ready. The stats report does not
block releases automatically. CI runs `mix gettext.check`, which rejects new
missing/fuzzy customer-facing translations, placeholder differences, missing plural
forms and catalogue/template mismatches in every domain. Admin/cinder coverage
can wait, but their structure and placeholders must remain valid. English empty
translations use the source. Each supported locale currently requires two plural
forms. Cinder's template comes from the installed dependency at
`deps/cinder/i18n/gettext/cinder.pot`; only Swedish and Finnish catalogues are
required for it. After upgrading Cinder, merge that template into both catalogues
with `mix gettext.merge <catalogue.po> deps/cinder/i18n/gettext/cinder.pot --no-fuzzy`.

Existing exceptions are recorded in `check-exceptions.json`, matched by language,
domain, context, exact source, plural index and translation. Every exception needs
a reason. Changed text is checked again, and stale exceptions fail until removed.
The initial list retains intentional language-code fallbacks, the existing privacy
URLs, and four Finnish recipient constructions pending native review. Add an
exception only after reviewing the actual wording; do not regenerate a baseline
to silence CI. Some route segments intentionally remain unchanged;
a missing route translation is a developer decision, not necessarily work for a
translator.

After changing email translations, run `mix print_emails sv fi en` and review the
rendered messages in every language.

## Editorial review in Git

Weblate is retired. Translation changes use the normal Git review workflow,
including receipt labels in `receipts.po`.

- Read the [glossary and style guide](glossary.md) before proposing wording.
- Track unresolved audit findings in the [review queue](review-queue.md). Identify
  entries by language, domain, context and exact source, not file line numbers.
- English remains the technical Gettext source. Jennie can approve Swedish as
  the editorial meaning for a specific entry; Finnish and English should then
  preserve that meaning. Existing Swedish is not automatically approved.
- Record AI review, native language review and Jennie's approval separately.
  Include reviewer/date and the exact wording reviewed (or Git revision).
  Approval of old wording does not transfer to a changed meaning.
- Keep usable translations while requesting review. Use fuzzy only when fallback
  to English is preferable to the existing wording, not as a general review flag.
- After a source change, extract/merge, inspect fuzzy matches, preserve valid
  translations and review all affected languages. Financial/legal meaning and
  cancellation policy need business approval, not just linguistic polish.

## For developers

Keep one backend, `EdenflowersWeb.Gettext`. Its default domain is `storefront`,
including imported `gettext`/`ngettext` macros and sigils without an override.
For runtime calls, pass the domain explicitly, for example
`Gettext.dgettext(EdenflowersWeb.Gettext, "storefront", message, bindings)`;
`Gettext.gettext(backend, message)` always looks in the literal `default` domain.

Web roles accept an explicit domain for their `~t` sigils:

```elixir
use EdenflowersWeb, {:live_view, gettext_domain: "admin"}
use EdenflowersWeb, {:html, gettext_domain: "shared"}
```

Other modules set the sigil domain directly:

```elixir
use GettextSigils,
  backend: EdenflowersWeb.Gettext,
  sigils: [domain: "emails"]
```

These settings affect **sigils only**. Ordinary calls outside the default domain
must use `dgettext`, `dngettext`, or `dpgettext` explicitly:

```elixir
dgettext("emails", "Hi %{name},", name: name)
dpgettext("admin", "subscription", "Cancelled")
```

For modules with mixed audiences, use explicit domain calls or a named sigil
modifier (as in `Edenflowers.Payments.Changes.Cancel`). Domains are a compile-time
choice, not inferred from the current route or user's role.

Only use `shared` for genuinely reusable components or messages; identical English
alone is not a reason to move unrelated page copy there. Avoid adding per-page
catalogues. Add translator comments where intent or placeholders are ambiguous.

`EdenflowersWeb.GettextTest` checks catalogue/template alignment and that admin
modules and email templates extract into the correct domain. The locale pin test
checks that every supported language has the required catalogues.

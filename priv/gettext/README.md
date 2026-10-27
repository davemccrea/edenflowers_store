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
```

The progress report separates critical and deferrable work by language and
catalogue. Missing translations and fuzzy entries are counted separately; obsolete
entries are excluded. English source text counts as ready. The report does not
block releases automatically. Some route segments intentionally remain unchanged;
a missing route translation is a developer decision, not necessarily work for a
translator.

After changing email translations, run `mix print_emails sv fi en` and review the
rendered messages in every language.

## For developers

After the receipts catalogues reach `main`, add a Weblate **Receipts** component
linked to Storefront's repository, with file mask
`priv/gettext/*/LC_MESSAGES/receipts.po`, source template
`priv/gettext/receipts.pot`, and language filter `^(fi|sv)$`.

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

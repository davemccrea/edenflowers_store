# Swedish and Finnish translation audit — 27 October 2026

## Result and limits

First linguistic pass completed against commit `b70f9c00`. Every active entry in the 14 checked-in Swedish/Finnish PO catalogs, including plural forms, was read alongside English and the other translation. All 35 receipt labels in both languages were also read. Selected ambiguous entries were traced to their call sites; this was not a visual browser review of every screen.

**This is an AI-assisted editorial audit, not native-translator approval.** “No issue identified” does not certify that wording cannot be improved. Swedish is the business/editorial language; English is the technical Gettext source. Differences from English are not automatically errors, and no entry has been assumed to have Jennie's approval merely because it is Swedish.

- **3,406 active Gettext entries**: 1,703 per language, including 19 plural entries per language.
- **70 receipt translations**: 35 per language, outside Gettext.
- **82 entries linked to 28 review groups**: corrections, optional improvements, business/source decisions, and receipt terminology.
- **3,386 entries with no issue identified in this first pass.**
- **8 route entries handled separately**: six intentional language-code fallbacks and two untranslated `privacy` routes requiring a developer decision, not automatic translation.
- No translations, fuzzy flags, Weblate settings, comments, labels, source copy, or production data were changed. Only audit artifacts were added.

### Coverage

| Catalog | Entries per language | Empty per language | First-pass reading |
| --- | ---: | ---: | --- |
| storefront | 752 | 1 | Complete |
| emails | 156 | 0 | Complete |
| shared | 35 | 0 | Complete |
| errors | 35 | 0 | Complete |
| routes | 13 | 4 | Complete; URL changes need developer coordination |
| cinder | 21 | 0 | Complete |
| admin | 691 | 0 | Complete |
| Receipt TOML | 35 | 0 | Complete; Weblate coverage unverified |

The coverage ledger is [translation-audit-2026-10-27-coverage.csv](translation-audit-2026-10-27-coverage.csv). It records every translation's source, domain, language, context, entry-start line and disposition. Plural forms were considered together as one catalog entry. `native-not-approved` describes the audit's lack of human sign-off; it does not revoke any approval that might already exist in Weblate.

Structured review notes are in [translation-audit-2026-10-27-findings.json](translation-audit-2026-10-27-findings.json). Gettext entry numbers in that file refer to the alphabetic/catalog order of this snapshot, not stable Weblate identifiers. Match by domain, context and exact source from the CSV before posting anything.

## Start with these corrections

| ID | Location | Finding and suggested direction |
| --- | --- | --- |
| T01 | `sv/fi storefront.po:2419` | **Related information** is empty in both languages and falls back to English. Suggest Swedish **Relaterad information**, Finnish **Lisätietoja**, subject to the site's heading vocabulary. |
| T02 | `sv storefront.po:3470` | **hör jag gärna av dig** is not idiomatic in the contact introduction. Suggested ending: **får du gärna höra av dig**. Preserve Jennie's surrounding copy. |
| T03 | `sv storefront.po:1496` | **café utrymme** should be a compound, e.g. **kaféutrymme** or **caféutrymme**. This is a point correction, not a reason to rewrite the paragraph. |
| T04 | `fi errors.po:115` | **Tämän kurssin varaus on päättynyt** can imply that a booking has ended. The action means new bookings have closed. Suggest **Tälle kurssille ilmoittautuminen on päättynyt.** |
| R01 | Receipt TOML, Swedish `total` | **Total** should preferably be **Totalt** or **Summa**, aligned with other totals. |

None of these has been changed. Existing understandable wording should not be removed from production merely to request a correction.

## Human translation and editorial review queue

These are review requests, not declarations that every current translation is wrong. A translator should be able to reject optional suggestions without changing a working translation.

| ID | Language / area | Concern and reviewer |
| --- | --- | --- |
| T05 | Finnish admin: **Fee** | **Hinta** is less precise than **Maksu** or **Toimitusmaksu** on the delivery fee chart (`admin.po:1135`). Finnish editor should match adjacent labels. |
| T06 | Both admin: **New custom order** | **Ny egen beställning / Uusi oma tilaus** can imply Jennie's own purchase. Jennie should choose wording for an order she enters for a customer, including ordinary catalog products and over-the-counter sales—not just bespoke work (`admin.po:1655`). |
| T07 | Swedish sizes | **Medel** is less natural as a bouquet size than **Mellan/Mellanstor** (`shared.po:80`). Jennie should approve the canonical size name before aligning catalog copy and database-managed sizes. |
| T08 | Finnish page titles | **Floristiikkakurssit Vaasa / Hautajaiskukat Vaasa / Hääkukat Vaasa** read like search keywords. Consider **Vaasassa** and a native editor's preferred course terminology (`storefront.po:1120,1299,3374`). |
| T09 | Finnish embedded address | Two descriptions retain **Myrvägen 1**, while standalone labels and emails use **Muurahaistie 1** (`storefront.po:1336,1815`). Both refer to the same place; the official Minimossen Finnish site uses Muurahaistie. Align the business's own Finnish address copy, not customer-entered addresses. |
| T10 | Both: card update explanations | **Ett nytt kort betalar inte… / Uusi kortti ei maksa…** is understandable but literal. Explain that *saving/changing the card* does not pay the existing unpaid order (`storefront.po:109,3692`). Keep the separate-payment requirement. |
| T11 | Both: subscription summary | **senast … före en bukett / … ennen kimppua** awkwardly uses a bouquet as a deadline. Say delivery or pickup, retaining `%{days}` (`storefront.po:1272`). |
| T12 | Both: about-page description | The sentence about making bouquets “from the first message” is strained. Finnish **lämpimiä … kimppuja** can imply physical warmth rather than warm colors. Jennie and native editors should clarify the intended style and personal service (`storefront.po:1780`). |
| T13 | Finnish: email change | **Vahvista uusi sähköpostiosoitteesi syöttämällä se** leaves “it” ambiguous. Prefer explicitly entering **koodi** (`storefront.po:3358`). |
| T14 | Finnish: subscriptions | Terminology varies between **kestotilaus**, **kukkatilaus** and **jatkuva kukkatilaus**. Agree a glossary distinguishing a standing subscription from an ordinary flower order (`storefront.po:3338,3811,3947`). |
| T15 | Both: wedding email tone | The wedding email mixes **er/ni** with **du/din**, and Finnish plural/formal address with singular address. This could intentionally distinguish the couple from the sender. Jennie should decide before a translator changes shared email strings (`emails.po:176,528,797,883`). Context-specific variants may be needed. |
| T16 | Finnish emails | Native polish suggested for **Oletko poissa, tai haluatko muutoksen?**, **Olen vastaanottanut maksusi %{amount}**, and **Seuraavat tilaukset ovat yllä olevaan hintaan** (`emails.po:103,272,858`). Meaning is understandable; do not mark fuzzy just for style. |
| R02 | Swedish receipt totals | **Gross → Totalt**, beside **Net → Netto**, is less explicit than **Inkl. moms / Exkl. moms** or **Brutto / Netto**. Native editor/accountant should approve the pair. |
| R03 | Finnish receipt VAT | **Vero / Verokanta** are generic. Consider **ALV / ALV-kanta**, consistent with the rest of the app. |
| R04 | Finnish receipt delivery | **Kotiinkuljetus / Kotiinkuljetusmaksu** narrows delivery to homes, though deliveries also go to churches, chapels and other venues. Consider **Toimitus / Toimitusmaksu** after checking receipt usage. |

### Four omitted placeholders: not four broken translations

A per-form check found these differences:

- Finnish storefront `%{name}'s address *` (`:52`).
- Finnish storefront `%{name}'s phone number *` (`:57`).
- Finnish storefront `I'll only call if I need to reach %{name} about the delivery.` (`:1551`).
- Finnish emails `You might like to let %{recipient} know it's waiting.` (`:675`).

All four use generic **vastaanottaja** instead of the person's name. That avoids unsafe Finnish inflection of arbitrary names and preserves the basic meaning. It is not a missing-variable runtime failure, but it does conflict with the repo's instruction to preserve placeholders exactly.

**T17/T18:** a Finnish translator and developer should either find natural constructions that preserve the name, or explicitly document the deliberate exception. Do not append a fixed Finnish case ending to arbitrary names without considering how names decline. No other `%{…}` placeholder differences were found by the per-form check. Special markers `{selector}` and `__N__` were also retained in the reviewed strings.

## Swedish-led intent and English-source work

These should go to Jennie/developer review rather than being assigned as ordinary target-language errors.

| ID | Finding | Recommended handling |
| --- | --- | --- |
| S01 | English **Charged %{date} / Charged to your card on %{date}.** can imply a completed charge. The call sites use the next charge date; Swedish **debiteras** and Finnish **veloitetaan** are appropriate. | Clarify English to future tense. Do **not** change the translations to past tense. See `subscription_manager.ex:616`, `account_live.ex:475`, and `Subscription.charged_on`. |
| S02 | **on request** becomes **enligt offert / tarjouksen mukaan**; **Corsage or pocket square** becomes **Corsage eller kavajblomma / Korsaasi tai taskukukka**. | Jennie should confirm the actual price/product meaning. English may need **price on request** or a more precise floral-product term. Do not translate approved Swedish literally back toward potentially ambiguous English. |
| S03 | The Finnish funeral introduction changes the Swedish idea of flowers as somewhere to rest one's eyes to saying farewell, and narrows traditional arrangements to **suruvihkot**. | Native Finnish florist/editor should review sensitivity and product scope against Jennie's approved Swedish (`storefront.po:267`). Not an automatic correction to English. |
| S04 | **Pause or cancel anytime** is translated faithfully, but the shop has a change deadline and an already committed bouquet can still arrive. | Coordinate source and translations to distinguish stopping later bouquets from cancelling the next bouquet. This is a shared source-policy ambiguity, not a translation-only defect. |
| S05 | Several admin **fulfillment** labels become **leverans/toimitus**, even when the state includes pickup. | Developer and native editor should agree language covering both modes. See the exact entries linked in the ledger; these are not all necessarily wrong in their individual screens. |
| S06 | **placed order** and **confirmed booking** are both called confirmed in one payment-validation message. | Preserve the distinction that accepting an order/booking does not mean payment has arrived (`admin.po:1809`). Jennie should approve understandable business terminology. |

Legal/privacy passages were included in the linguistic pass. No claim of legal validation is made. A translator can improve language but should not independently change cancellation rights, retention periods, legal bases, refund obligations or payment deadlines. Those changes need the business owner and, where necessary, a qualified legal reviewer.

## Context checks that prevented false positives

- **Yes, cancel** is a FAQ sentence fragment, not a cancellation button. Its Finnish explanatory form is appropriate in the assembled sentence (`faq_live.ex:165`). My preliminary observation that it was a button error was withdrawn after tracing the call site.
- The future-tense charge translations are correct; the ambiguous wording is English. My preliminary past/future mismatch observation was withdrawn after tracing the next-charge calculation.
- Finnish FAQ fragments intentionally carry case across linked text: for example **Jos en pääse sisään, toimitusehdoissa kerrotaan, mitä seuraavaksi tapahtuu.** Do not edit isolated fragments without reconstructing the paragraph.
- Finnish **Muurahaistie 1** is supported by the official Minimossen site. It is not an invented translation of a street name.
- **Begravning / Hautajaiset** for the funeral page and route is contextually appropriate despite English **Condolences**. Changing the URL to a more literal translation would be unjustified.
- Finland-Swedish **Vasa**, **Korsholm**, **Vändagen**, **rat**, and **drar kurser** must not be automatically replaced with Sweden-centric or supposedly more literal equivalents. Jennie's local voice matters.
- The language-code routes `en`, `fi`, `sv` intentionally fall back unchanged. The empty `privacy` route is a separate URL decision; translating it requires route/redirect coordination.

## Email rendering and technical checks

Ran:

```text
mix gettext.stats
mix print_emails sv fi en
```

The stats task independently confirmed the inventory counts and that no entries are currently fuzzy. The email task succeeded for **99 scenarios per language, 297 renders total**. I read the deduplicated rendered text from all three languages, including singular/plural booking confirmations, delivery/pickup, partial payments, refunds, subscriptions and wedding enquiries. This checks composed text, not visual email-client layout or native approval.

Local artifacts, ignored by Git:

- `tmp/translation-audit/rendered-emails.md`: full preview output.
- `tmp/translation-audit/rendered-unique.txt`: unique composed lines reviewed.
- `tmp/translation-audit/inventory.json`: parsed active entries and comments.
- `tmp/translation-audit/mechanical-issues.json`: four placeholder differences.

A GNU `msgfmt --check` attempt stopped at Swedish `cinder.po` because it lacks a charset header; it also reported incomplete administrative metadata in `admin.po`. This is catalog housekeeping, not evidence that a translation is linguistically wrong. The command did not validate all catalogs, and no claim of a full GNU validation pass is made. No extraction/merge was run because that could rewrite catalogs.

## Best way to hand the findings to Weblate

**Default: a language-specific review comment, optionally a suggestion, while retaining the current usable translation.**

Use a consistent comment shape:

```text
Audit T02 — Swedish — correction — native review requested
Context: contact-page introduction.
Current concern: “hör jag gärna av dig” is not idiomatic.
Suggested wording: “… får du gärna höra av dig.”
Preserve Jennie's intended meaning and surrounding voice.
No fuzzy flag requested; existing copy remains understandable.
```

1. Before posting, authenticate and inspect the live Weblate component, revision, existing comments, glossary, pending work and exact unit identity. The anonymous API returned no visible projects, so this audit cannot verify live revision, pending translations, permissions or existing approvals. It does **not** establish that the project is absent.
2. Compare current live text against this snapshot; discard or update findings already resolved by translators. Avoid duplicate comments on repeated runs.
3. Post translation comments for target-language wording; source comments/source review for S01–S06 and unresolved business intent. Source comments should explicitly explain when Swedish may be authoritative.
4. Use suggestions for proposed wording when helpful, with human acceptance. Do not silently replace Jennie's Swedish or a translator's newer work.
5. Use optional labels such as `audit-native-review`, `audit-source-review` and `swedish-authoritative` after checking the installed version's label scope and permissions. A label is workflow metadata, not a changed Gettext source language. If labels apply to the source across languages, retain the affected language in the comment rather than assuming a label is language-specific.
6. Reserve **Needs editing/fuzzy** for genuinely unusable or meaningfully unsafe target text where intentionally falling back to English is acceptable. For this audit, blanket fuzzing is not recommended. An English-source defect is not a reason to invalidate a correct Swedish/Finnish translation.
7. Human approval/review and editorial authority are separate. If review workflow is enabled, Jennie can approve Swedish wording; the authority note explains that English/Finnish should follow its meaning. Approval can restrict subsequent edits to reviewers, so confirm team roles before enabling it.
8. When approved Swedish represents new copy, developer updates English in code, extracts/merges with translator work reconciled, preserves the intended Swedish, and gets Finnish updated. Recheck comments/authority after the source changes; a historical approval must not be assumed to cover new meaning.
9. After email changes, rerun `mix print_emails sv fi en` and review all languages. Coordinate any URL translation with a developer. No translation-only Git edits should bypass pending Weblate work.

Upstream Weblate now also documents a **custom source language per project/language**, with parent-language changes marking dependent translations for editing. This could eventually let Finnish use Swedish editorial text while identifiers stay English. It is not a per-string “definitive” flag, has significant state/fallback implications, and the installed instance's support/configuration has **not** been verified. Do not enable it as part of this audit.

## Remaining coverage gaps before calling this a whole-website audit

1. **Live Weblate state:** pending translator edits, glossary, approvals, labels and deployed version were not accessible anonymously. This report audits checked-in catalogs, not uncommitted translator work.
2. **Database-managed copy:** products, product categories, courses and fulfillment options use `AshTranslation.Resource`. Their live names/descriptions are not in these PO files. No production database was accessed. A controlled read-only export is needed to review actual customer-visible records; local seeds are not proof of production copy.
3. **Receipt workflow:** `priv/receipts/translations.toml` was reviewed, but no dedicated receipt Weblate component/configuration is checked in here. Verify its live coverage. If absent, add a coordinated component or migrate labels into the established workflow before expecting translators to fix R01–R04 in Weblate.
4. **Browser/layout:** long Finnish labels, accessibility output, line wrapping and every assembled screen were not visually tested. Selected source-call-site checks do not replace that pass.
5. **Workflow documentation drift:** project instructions mention `.github/workflows/translations.yml`; that file is absent from this checkout. CI does include `weblate-translations`, but automatic PR creation has not been verified. Verify the actual delivery path before relying on it.
6. **Human decisions:** Jennie has not designated individual Swedish entries as authoritative in this audit, and no native translator has accepted the proposed improvements.

## Sources

- Repository: `priv/gettext/README.md`, `CONTEXT.md`, current catalogs, `Format.weekday_date/2`, referenced views/resources and email previews.
- Official Finnish Minimossen address: https://www.stormossen.fi/minimossen/ (accessed 27 October 2026; linked from https://minimossen.fi/).
- Weblate upstream documentation: https://github.com/WeblateOrg/weblate/blob/main/docs/user/translating.rst (comments, suggestions, labels).
- Weblate upstream workflows: https://github.com/WeblateOrg/weblate/blob/main/docs/workflows.rst (review/approval, fuzzy states and custom source language). Upstream `main` is not proof of the installed instance's features.

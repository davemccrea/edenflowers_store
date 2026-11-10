---
id: TASK-186
title: Support only English and Swedish in admin without changing customer languages
status: done
assignee: []
created_date: '2026-11-09 20:45'
updated_date: '2026-11-09 20:56'
labels:
  - admin
  - developers
dependencies: []
priority: low
type: chore
ordinal: 351000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Admin uses English and Swedish only.

**Why:** Finnish back-office translations add maintenance work without helping the shop. Customer-facing Finnish must remain fully supported.

Confirmed with the user: remove Finnish admin/cinder catalogues, including pending Finnish admin catalogue edits. Keep an independent admin language preference, defaulting Finnish visitors to Swedish; preserve customer language selectors, records, email previews and receipt languages.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Admin offers only English and Swedish, uses Swedish for Finnish visitors without an admin preference, and remembers a separate admin preference.
- [x] #2 Changing the admin language preserves the storefront language and customer-facing Finnish support.
- [x] #3 Finnish admin/cinder catalogues are removed; extraction and validation support the deliberate domain-specific locale policy.
- [x] #4 Agent and translation guidance state English/Swedish-only admin and preserve Finnish customer-facing translations.
- [x] #5 Focused regression tests and translation checks pass.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Centralize catalogue locale policy (admin en/sv, Cinder sv, customer domains en/sv/fi); add gettext.update to extract and merge only supported domain/locale pairs, and update check/stats/pin tests.
2. Add a separate admin_locale session preference, admin HTTP plug and LiveView hook mode; resolve valid prior public en/sv preference or fall back to Swedish. Restrict only admin interface picker and add admin-specific selection endpoint, preserving customer locale controls.
3. Remove authorized Finnish admin/cinder catalogues. Update CLAUDE.md and translation README with policy and safe update command.
4. Add focused catalogue and HTTP/LiveView regressions, run update/check/stats/extraction freshness and focused tests, review diffs for untouched Finnish customer catalogues and preservation of unrelated work.

Catalogue policy lives in Edenflowers.TranslationCatalogues (separate from existing AshTranslation helpers). gettext.update merges project templates only; dependency-owned Cinder remains updated manually as documented.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Focused regression run: 35 tests, 0 failures. mix gettext.update --no-fuzzy: zero new/removed/reworded messages in every retained catalogue; Finnish admin/cinder stayed absent. gettext.check passed with the existing nine documented exceptions; gettext.stats confirms full Finnish customer-facing coverage apart from the existing three intentional route fallbacks. extract --check-up-to-date passed. Catalogue semantic diff audit found no changed source or translation wording; only extraction references and reordered existing Swedish translator comments. Full just test gate is running.

Full initial just test gate: JavaScript passed; 2191 Elixir tests ran, with three failures solely from old Finnish admin expectations (Cinder controls and two payment refusal cases). Updated those regression tests for Swedish admin support. Focused affected suites then passed 128 tests, 0 failures. Full Elixir rerun uses the same seed 255517; awaiting completion. Strict Credo and warnings-as-errors compilation passed, as did changed-file formatting and git diff --check.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed Finnish admin/cinder catalogues while preserving Finnish customer-facing domains. Admin now offers Swedish/English with a separate session preference and Swedish fallback for Finnish visitors. Added domain-specific catalogue policy and gettext.update to avoid recreating unsupported Finnish admin catalogues; updated agent/translation guidance and regression tests. Verification: JavaScript suite passed; full Elixir rerun passed 2191 tests, 0 failures, 1 skipped (seed 255517). Translation update/check/stats and extraction freshness passed, alongside strict Credo, warnings-as-errors compilation, changed-file formatting and git diff --check. Retained catalogue wording unchanged; only source-reference updates and reordered existing Swedish translator comments.
<!-- SECTION:FINAL_SUMMARY:END -->

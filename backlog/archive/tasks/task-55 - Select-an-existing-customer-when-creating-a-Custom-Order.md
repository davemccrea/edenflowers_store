---
id: TASK-55
title: Select an existing customer when creating a Custom Order
status: done
assignee: []
created_date: '2026-10-18 20:19'
updated_date: '2026-10-18 21:31'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 121000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Let Jennie select an existing Customer in the new Custom Order form and prefill their contact information.

**Why:** Jennie should not have to retype a returning Customer's details when taking an order. Reusing saved contact information makes entering orders quicker and reduces mistakes.

Add a customer selector to the new Custom Order form. Selecting a Customer prefills the Customer contact fields (name, email and phone) with their saved details where available. Jennie can review and edit those details for this order without changing the saved Customer record. Keep manual entry available for new Customers or orders where Jennie does not select an existing Customer. Customer selection must not overwrite a separate Recipient's details on a gift order.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie can find and select an existing Customer in the new Custom Order form.
- [x] #2 Selecting a Customer prefills their available name, email and phone in the Customer contact fields; missing details can be entered manually.
- [x] #3 Jennie can edit the prefilled contact information and place the order with those details without changing the saved Customer record.
- [x] #4 Jennie can still create a Custom Order by entering contact information manually without selecting an existing Customer.
- [x] #5 Selecting a Customer does not overwrite a separate Recipient's details on a gift order.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented and reviewed: LiveSelect 1.7.5 single-select customer search reuses Accounts.search_customers, supports keyboard selection and clearing, and matches incumbent admin inputs, menus, theme colors, spacing and focus styles. Prefills saved name/email and latest available buyer phone through an Orders read action; online gift pickups are included while separate gift Recipient phones are excluded. Selected Customer is linked using Ash manage_relationship without upserting saved contact details. Manual entry and order-only edits remain available. Gift Recipient fields, nested order lines and edited contacts survive validation and dedicated LiveView form recovery. Accessibility adapter supplies combobox/listbox semantics and actual selected state missing from LiveSelect. Ash/Phoenix, spec and Ponytail reviews completed; actionable findings fixed and targeted re-review passed. Final verification: source .env && mix precommit passed (1360 tests, 0 failures; warnings-as-errors compile, codegen check, formatting, strict Credo); node --test test/customer_select_keyboard_test.mjs passed (2 tests); assets build and git diff --check passed. Browser visual verification unavailable. New UI strings use GettextSigils; translation extraction/generation awaits user opt-in.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @opencode
created: 2026-10-18 21:27

---

Follow-up: reproduced selected-label blanking with the installed LiveSelect 1.7.5 bundled select callback (Node regression failed: focus must not blank the selected customer). Component focus/click emits current_text from the search buffer, which selection clears, while retaining the selected ID; its client writes that empty string into the input. Customer-specific hook wrapper now preserves visible text for focus/click responses and selects the committed label for replacement, without intercepting typing, clearing or blur restoration. Keyboard-active options use bg-primary/text-primary-content instead of menu-active, with matching ARIA active-descendant detection. Verification: 31 targeted CustomOrderLive tests and 3 Node tests passed; mix assets.build and targeted mix format --check-formatted passed. Browser visual verification unavailable. Follow-up keeps the completed spec status unchanged; no dependency edits or commit.

---

author: @claude
created: 2026-10-18 21:31

---

Idiomatic integration refinement supersedes the focus workaround above: removed event interception. A normal additional handleEvent listener now shows the committed customer label as placeholder context while LiveSelect manages its native empty search buffer, typing, selection and clearing. Checked installed public APIs: keep_options_on_select preserves the search query/options, not the selected label, and phx-focus/phx-blur are notifications. Retained supported active_option_class theming and necessary ARIA adaptation. Shortened helper to Search by name or email. and removed redundant selected-customer guidance. Verified 31 targeted LiveView tests, 3 bundled-hook Node regressions, assets build and formatting checks; browser visual verification unavailable.

---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Jennie can search for and select a returning Customer in a site-styled LiveSelect combobox, edit their order-only contact details, or enter details manually, while preserving saved Customer records and separate Recipient information.
<!-- SECTION:FINAL_SUMMARY:END -->

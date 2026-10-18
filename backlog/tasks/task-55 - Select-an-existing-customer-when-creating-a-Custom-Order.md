---
id: TASK-55
title: Select an existing customer when creating a Custom Order
status: ready-for-agent
assignee: []
created_date: '2026-10-18 20:19'
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
- [ ] #1 Jennie can find and select an existing Customer in the new Custom Order form.
- [ ] #2 Selecting a Customer prefills their available name, email and phone in the Customer contact fields; missing details can be entered manually.
- [ ] #3 Jennie can edit the prefilled contact information and place the order with those details without changing the saved Customer record.
- [ ] #4 Jennie can still create a Custom Order by entering contact information manually without selecting an existing Customer.
- [ ] #5 Selecting a Customer does not overwrite a separate Recipient's details on a gift order.
<!-- AC:END -->

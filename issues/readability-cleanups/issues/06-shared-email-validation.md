# Validate email addresses in one place

Status: ready-for-agent
Type: refactor

## Problem

The same email check, `~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/` with "Must be a valid email address", is written out six times:

- `Order`: `place_custom`, `submit_contact_details`, `edit` (on `:customer_email`)
- `CourseRegistration`: `register`, `add_manually` (on `:email`)
- `AccountLive`: the email-change form, as `String.match?/2`

A change to what counts as a valid address has to find all six.

## What to build

- A validation module, e.g. `Edenflowers.Validations.Email`, taking the attribute: `validate {Edenflowers.Validations.Email, attribute: :customer_email}`. It owns the regex and the message (through gettext, if the message is shown to customers).
- `AccountLive` calls a public `valid?/1` on the same module, or better, relies on the `User` action's own validation if the email change goes through one.

## Tests

- A unit test for the module: valid, missing `@`, missing dot after `@`, whitespace.
- The existing suite passes.

## Acceptance criteria

- [ ] The regex exists once
- [ ] The existing suite passes

## Comments

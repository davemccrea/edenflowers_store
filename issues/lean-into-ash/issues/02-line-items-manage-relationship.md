# Manage a custom order's lines with manage_relationship

Status: needs-triage
Type: refactor

## Problem

When Jennie places or edits an order, `Changes.ReplaceLineItems` does by hand what `manage_relationship` does: it loads the order's lines, updates the kept ones (`set_quantity`), destroys the missing ones (`remove_item`), and creates the new ones (`add_line_item` for a catalogue variant, `add_custom_item` for one she describes). `EnteredLineItems` first parses the form's maps into tuples, and `Validations.EnteredLineItems` reports the first bad line by its number.

## The idea

- One `LineItem` create action for entered lines, taking either `product_variant_id` or a description, unit price and `tax_rate_id`, with `PopulateFromVariant` only for the first kind.
- On `place_custom` and `edit`: `change manage_relationship(:line_items, type: :direct_control, on_match: {:update, :set_quantity}, on_no_match: {:create, :enter}, on_missing: {:destroy, :remove_item})`.
- `OrderFormLive` uses AshPhoenix nested forms (`inputs_for`), so each line's errors land on its own fields. `EnteredLineItems` and its validation go.

## To decide

- The order log entry: `ReplaceLineItems` compares the entered lines with the stored ones to write "2 × Rose bouquet, …" into paper-trail metadata, or skip a version when nothing changed. That comparison has to stay, as a before-action change reading the argument.
- Stock: `AdjustStock` returns then takes the whole order around the replacement today. It has to keep running after `manage_relationship`.
- A kept line keeps the price it was sold at. `on_match: :set_quantity` already only accepts `quantity`, so that holds.
- Cost: the order form is 780 lines; the nested-forms change is most of the work. Worth it if the form is being touched anyway.

## Comments

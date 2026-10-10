# Show the same-day fee on the checkout calendar

Status: ready-for-agent

## What to build

Tell customers about the same-day fee before they choose a date, so anyone who doesn't need it today can pick tomorrow.

- On the checkout date calendar, today's cell shows a small "+€5" (the option's same-day fee) under the date when today is bookable and the fee is non-zero. Use the calendar's existing `day_decoration` slot, which already renders key-date icons.
- When today is selected, a line under the calendar reads "Same-day delivery +€5.00 · order by 14:00" (fee and the option's `order_deadline`). For pickup options it reads "Same-day pickup".
- Nothing extra shows when the fee is 0, when today isn't bookable (deadline passed, same-day disabled, closed day), or when another date is selected.

```
Delivery date *
┌─────────────────────────────┐
│  Mo  Tu  We  Th  Fr  Sa  Su │
│       ⓾  11  12  13  14  15 │
│      +€5                    │
└─────────────────────────────┘
Same-day delivery +€5.00 · order by 14:00
```

## Acceptance criteria

- [ ] Today's cell shows the fee only when today is bookable and the fee is above 0
- [ ] Selecting today shows the fee and deadline line; selecting another day hides it
- [ ] Key-date icons on today still render alongside the fee
- [ ] Amounts use `Format.currency` and times `Format.time` in the customer's locale
- [ ] User-facing strings use `~t` and are translated

## Blocked by

- `01-charge-same-day-fee.md`

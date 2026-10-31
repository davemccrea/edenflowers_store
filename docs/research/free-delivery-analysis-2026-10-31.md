# Free delivery: business case and old-site data, 31 October 2026

## Question

Should Eden Flowers offer free delivery, now that it has a low-rent shop in
Minimossen as well as the online store? The new site had only just gone live,
so it had too few orders to say anything. This note uses the old site's
database instead, from December 2020 to March 2026.

The current rule, as of commit `37f513f8`: a cart holding a free-delivery
product pays nothing up to the delivery option's `free_dist_km` (5 km), then
the base price plus the per-km price for each km beyond. Other carts pay the
base price plus the per-km price for the whole distance.

## Arguments

For free delivery:

- Online flowers are mostly gifts for someone else, so pickup is often not an
  option, and a fee that appears at checkout is a classic reason carts get
  abandoned. "Free delivery in Vaasa" stands out against the national networks.
- Vaasa is compact: most deliveries are short.
- Low rent leaves margin to treat delivery as marketing.
- It suits subscriptions: fixed addresses on predictable days.
- It's simple to say.

Against:

- Jennie's time is the scarce resource. The shop is unattended while she
  delivers.
- Free delivery could pull orders away from pickup, which brings people into
  the shop.
- Order values are small (about €41), so a typical fee is a big share of the
  sale.
- Peak days (Valentine's, Mother's Day) already strain delivery capacity, and
  customers on those days care little about price.
- Free delivery is hard to take back once given.

## Data and method

- Source: `heroku_db.dump` in the repo root (gitignored), restored into a
  scratch database with `pg_restore --no-owner --no-acl`.
- Included orders: not deleted, with `payment_status` in `stripe_succeeded`,
  `invoice_pending`, `invoice_paid` or `gift_card_or_promo_paid`.
- Excluded: about 80 orders from test or developer addresses (`dmccrea.me`,
  David M's gmail, first name "Test"), mostly from 2020 and 2021.
- The old site created a new `customers` row for every order, so repeat
  customers are matched on `lower(email)`.
- Amounts are integer cents. `addresses.distance` is the one-way driving
  distance in metres.
- Distance origin: the old site's zero-distance point (63.12437, 21.60062,
  Myrvägen) is about 160 m from the new site's HERE origin (63.1243488,
  21.5974075, in `lib/edenflowers/external/here_api.ex`), so the old distances
  apply to the shop as they are. The origin stayed the same over the old site's
  life: 55 of 63 addresses ordered to more than once kept the same distance.
- Old fee rule: free to about 8 km until mid-2021, then free to 5 km. Beyond
  that, about €2 per km (a fitted line with r² 0.85).

## Findings

### Free delivery costs little at this volume

| Year | Orders | Deliveries | Pickup | Deliveries free | Fees collected | Bouquet sales | Average order |
|---|---|---|---|---|---|---|---|
| 2020 (Dec) | 21 | 21 | 0% | 81% | €35 | €743 | €35.38 |
| 2021 | 218 | 216 | 1% | 92% | €175 | €8,723 | €40.01 |
| 2022 | 151 | 136 | 10% | 76% | €264 | €6,244 | €41.35 |
| 2023 | 84 | 71 | 15% | 70% | €188 | €3,542 | €42.17 |
| 2024 | 66 | 57 | 14% | 72% | €144 | €2,719 | €41.20 |
| 2025 | 69 | 58 | 16% | 76% | €178 | €2,858 | €41.41 |
| 2026 (to Mar) | 19 | 17 | 11% | 65% | €55 | €858 | €45.13 |

- The median delivery was about 4 km from the shop, and 90% were within
  about 7 km.
- From 2023 on, about 89% of delivery days had a single drop: each delivery is
  its own trip.
- At about 45 free deliveries a year and an 8 km round trip each, the mileage
  cost is around €200 a year at the tax mileage allowance (about €0.55/km, not
  checked), plus perhaps 15 to 20 hours of Jennie's time.
- Customers 5 to 10 km away who paid about €8 spent slightly more per order
  (€44.58) than those within 5 km (about €41), so paying a fee didn't go with
  smaller orders.

### Free delivery didn't take orders from pickup

Pickup grew from 1% of orders (2021) to 16% (2025), while delivery within
5 km stayed free.

### Customers who paid a fee came back less (a hint, not proof)

The mid-2021 change from free to about 8 km to free to 5 km moved the 5 to
8 km band from free to paid (about €7.50), while the other bands stayed the
same. Share of first-time delivery customers (first order before 2025) who
ordered again:

| First order | 0 to 5 km (always free) | 5 to 8 km | 8 km+ (always paid) |
|---|---|---|---|
| Before Jul 2021 (5 to 8 km free) | 53% (n=74) | **47%** (n=32) | 7% (n=15) |
| Jul 2021 to 2024 (5 to 8 km paid) | 31% (n=123) | **15%** (n=34) | 8% (n=13) |

When free, the 5 to 8 km band came back almost as often as nearby customers.
Once paid, its return rate fell to half of theirs.

Caveats:

- The 5 to 8 km cells are small, about 33 customers each.
- The earlier group had more time to come back.
- Counted by average later orders instead of return rate, the gap mostly goes
  away (0.50 later orders vs 0.63 for 0 to 5 km in the paid era), because a
  few loyal customers dominate the totals.

Across all customers, 40% of those whose first delivery was free ordered
again, against 9% of those who paid. That comparison mixes in distance,
though.

### Delivery policy didn't drive the decline in sales

Orders fell from 218 (2021) to 66 to 84 a year from 2023, while the delivery
rules didn't change from 2022 on. The 2021 peak looks like lockdown-era
demand: the busiest day was 36 deliveries on 11 February 2021. Demand fell for
other reasons.

### Peak days

The busiest days are always the days before Valentine's Day and the Saturday
before Mother's Day: 8 to 13 deliveries in recent years, against about one on
a normal delivery day.

## Recommendations

- Keep free delivery within 5 km. It costs about €200 a year and covers three
  quarters of deliveries.
- Consider trying a free radius of about 8 km (`free_dist_km` on the delivery
  option). That would waive about €100 to €150 a year in fees, and the old data
  suggests it could roughly double how often those customers come back.
- Don't make delivery free past about 8 km. Customers there rarely came back
  even when delivery was free.
- Keep subscription deliveries free.
- Batching (set delivery days or runs) only pays off once volume grows.
- The bigger lever is getting new customers, not delivery pricing.

## Rerunning on the new site

[`free-delivery-queries.sql`](free-delivery-queries.sql) is a read-only
report on the new site's schema:

- fee settings
- orders by month
- deliveries by distance band
- free-delivery carts vs other carts
- the checkout funnel
- share of carts placed, by delivery fee shown
- deliveries per delivery day
- the busiest days
- how free-delivery products sell

It runs inside `BEGIN TRANSACTION READ ONLY` and rolls back. Run it once there
are about 100 delivery orders, or after any change to the free radius:

```
ssh edenflowers-production "sudo -u postgres psql -X -d edenflowers_store_prod -f -" \
  < docs/research/free-delivery-queries.sql > tmp/free-delivery-report.txt
```

Two things the database can't show: how long a delivery takes Jennie (ask her
to note it), and where checkouts drop off (use Umami's "Checkout step"
events).

The return-rate query on the old database, for reference:

```sql
create temp view r as
select o.*, lower(c.email) email, d.pickup, d.delivery_cost, a.distance
from orders o
join customers c on c.id = o.customer_id
join deliveries d on d.order_id = o.id
join addresses a on a.id = d.address_id
where not o.is_deleted
  and o.payment_status in ('stripe_succeeded', 'invoice_pending', 'invoice_paid', 'gift_card_or_promo_paid')
  and not (lower(c.email) like '%dmccrea.me' or (c.first_name = 'David' and c.last_name like 'M%') or c.first_name = 'Test');

with f as (select distinct on (email) email, pickup, distance, created_at from r order by email, created_at),
     n as (select email, count(*) n from r group by 1)
select case when f.created_at < '2021-07-01' then 'free to 8 km' else 'free to 5 km' end era,
       case when distance < 5000 then '0-5' when distance < 8000 then '5-8' else '8+' end band,
       count(*) customers, round(100.0 * avg((n.n > 1)::int)) pct_returned
from f join n using (email)
where not f.pickup and f.created_at < '2025-01-01'
group by 1, 2 order by 1, 2;
```

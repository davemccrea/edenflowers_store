-- Read-only: the whole script runs in a READ ONLY transaction and rolls back.
BEGIN TRANSACTION READ ONLY;

\set o '(SELECT o.*, EXISTS (SELECT 1 FROM line_items li WHERE li.order_id = o.id AND li.free_delivery) AS free_cart, (SELECT coalesce(sum(li.unit_price * li.quantity), 0) FROM line_items li WHERE li.order_id = o.id) AS items, CASE WHEN EXISTS (SELECT 1 FROM line_items li WHERE li.order_id = o.id AND li.free_delivery) AND o.fulfillment_fee_override IS NULL AND o.quoted_free_delivery_fee IS NOT NULL THEN o.quoted_free_delivery_fee ELSE o.quoted_fulfillment_fee END AS fee FROM orders o) o'

\echo '== 1. Fee settings'
SELECT name, fulfillment_method, rate_type, base_price, price_per_km, free_dist_km, max_dist_km,
       mileage_rate, fuel_price, fuel_consumption
FROM fulfillment_options ORDER BY sort_key;

\echo '== 2. Placed, not cancelled: by month, origin, method'
SELECT to_char(ordered_at AT TIME ZONE 'Europe/Helsinki', 'YYYY-MM') AS month, origin, fulfillment_method,
       count(*) AS n, round(avg(items), 2) AS avg_items, round(avg(fee), 2) AS avg_fee
FROM :o WHERE state = 'placed' AND fulfillment_status <> 'cancelled'
GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

\echo '== 3. Placed deliveries by one-way distance'
SELECT CASE WHEN distance < 2000 THEN '0-2 km' WHEN distance < 5000 THEN '2-5 km'
            WHEN distance < 10000 THEN '5-10 km' WHEN distance < 20000 THEN '10-20 km'
            WHEN distance IS NULL THEN 'unknown' ELSE '20+ km' END AS band,
       count(*) AS n, round(avg(fee), 2) AS avg_fee, round(avg(items), 2) AS avg_items,
       round(100.0 * avg(free_cart::int), 0) AS pct_free_cart
FROM :o WHERE state = 'placed' AND fulfillment_status <> 'cancelled' AND fulfillment_method = 'delivery'
GROUP BY 1 ORDER BY min(coalesce(distance, 1e9));

\echo '== 4. Online orders: free-delivery carts vs others (pickup share, AOV, fee)'
SELECT free_cart, count(*) AS n,
       round(100.0 * avg((fulfillment_method = 'pickup')::int), 0) AS pct_pickup,
       round(avg(items), 2) AS avg_items, round(avg(fee) FILTER (WHERE fulfillment_method = 'delivery'), 2) AS avg_delivery_fee,
       round(sum(quoted_fulfillment_fee - fee) FILTER (WHERE fulfillment_method = 'delivery'), 2) AS fees_waived
FROM :o WHERE state = 'placed' AND fulfillment_status <> 'cancelled' AND origin = 'online'
GROUP BY 1;

\echo '== 5. Online carts with lines, by checkout step reached (unplaced = abandoned or in progress)'
SELECT state, count(*) AS n, round(avg(items), 2) AS avg_items,
       count(*) FILTER (WHERE quoted_fulfillment_fee IS NOT NULL) AS with_fee_quote
FROM :o WHERE origin = 'online' AND items > 0
GROUP BY 1 ORDER BY 1;

\echo '== 6. Online delivery carts that got a fee quote: placed rate by fee shown'
SELECT CASE WHEN fee = 0 THEN 'a: free' WHEN fee < 5 THEN 'b: <5' WHEN fee < 10 THEN 'c: 5-10'
            WHEN fee < 15 THEN 'd: 10-15' ELSE 'e: 15+' END AS fee_band,
       count(*) AS quoted, count(*) FILTER (WHERE state = 'placed') AS placed,
       round(100.0 * avg((state = 'placed')::int), 0) AS pct_placed, round(avg(items), 2) AS avg_items
FROM :o WHERE origin = 'online' AND items > 0 AND fulfillment_method = 'delivery' AND fee IS NOT NULL
  AND inserted_at < now() - interval '2 days'
GROUP BY 1 ORDER BY 1;

\echo '== 7. Deliveries per delivery day (batching)'
SELECT count(*) AS delivery_days, round(avg(n), 2) AS avg_per_day, max(n) AS max_per_day,
       count(*) FILTER (WHERE n = 1) AS single_drop_days
FROM (SELECT fulfillment_date, count(*) AS n FROM :o
      WHERE state = 'placed' AND fulfillment_status <> 'cancelled' AND fulfillment_method = 'delivery'
      GROUP BY 1) d;

\echo '== 8. Busiest fulfillment days'
SELECT fulfillment_date, count(*) FILTER (WHERE fulfillment_method = 'delivery') AS deliveries,
       count(*) FILTER (WHERE fulfillment_method = 'pickup') AS pickups
FROM :o WHERE state = 'placed' AND fulfillment_status <> 'cancelled'
GROUP BY 1 ORDER BY 2 DESC, 3 DESC LIMIT 10;

\echo '== 9. Free-delivery products and how they sell'
SELECT p.name, p.free_delivery, count(DISTINCT li.order_id) AS orders
FROM products p
LEFT JOIN product_variants pv ON pv.product_id = p.id
LEFT JOIN line_items li ON li.product_variant_id = pv.id
LEFT JOIN orders x ON x.id = li.order_id AND x.state = 'placed'
WHERE x.id IS NOT NULL OR p.free_delivery
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 25;

ROLLBACK;

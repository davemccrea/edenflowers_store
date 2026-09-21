# Regenerates the JSON fixtures beside this file through the real
# Receipt.build_payload/1, so a Typst preview can't drift from what customers
# actually receive:
#
#     source .env && mix run priv/receipts/sample/regenerate.exs
#
# The LineItem/Order calculations need a database, so the money is derived here
# instead — keep these formulas in step with line_item.ex and order.ex.
alias Edenflowers.Orders.{LineItem, Order}
alias Edenflowers.Orders.Receipt

d = &Decimal.new/1

line = fn {name, size, price, qty, rate}, discount_rate ->
  price = d.(price)
  rate = d.(rate)
  subtotal = Decimal.mult(price, qty)
  discount = Decimal.mult(subtotal, discount_rate)

  %LineItem{
    product_name: name,
    variant_size: size,
    quantity: qty,
    unit_price: price,
    unit_price_ex_tax: Decimal.div(price, Decimal.add(1, rate)),
    tax_rate: rate,
    subtotal: subtotal,
    discount: discount,
    total: Decimal.sub(subtotal, discount)
  }
end

build = fn opts ->
  discount_rate = d.(opts[:discount_rate] || "0")
  fee = d.(opts[:fee] || "0")
  fee_rate = d.(opts[:fee_rate] || "0.255")
  line_items = Enum.map(opts[:line_items], &line.(&1, discount_rate))
  items_subtotal = line_items |> Enum.map(& &1.total) |> Enum.reduce(&Decimal.add/2)

  %Order{
    locale: opts[:locale],
    order_reference: opts[:order_reference],
    ordered_at: opts[:ordered_at],
    customer_name: "Anna Lindqvist",
    customer_email: "anna.lindqvist@example.fi",
    fulfillment_method: opts[:fulfillment_method],
    fulfillment_date: ~D[2026-05-16],
    fulfillment_fee: fee,
    fulfillment_tax_percentage: fee_rate,
    recipient_name: opts[:recipient_name],
    recipient_phone_number: opts[:recipient_phone_number],
    delivery_address: opts[:delivery_address],
    delivery_instructions: opts[:delivery_instructions],
    card_message: opts[:card_message],
    promotion_applied?: Decimal.compare(discount_rate, 0) == :gt,
    discount: line_items |> Enum.map(& &1.discount) |> Enum.reduce(&Decimal.add/2),
    items_subtotal: items_subtotal,
    grand_total: Decimal.add(items_subtotal, fee),
    line_items: line_items
  }
end

names = %{
  "sv" => %{posy: "Vårbukett", euc: "Eukalyptusbukett", card: "Handskrivet kort", choc: "Choklad"},
  "fi" => %{posy: "Kevätkimppu", euc: "Eukalyptuskimppu", card: "Käsinkirjoitettu kortti", choc: "Suklaata"},
  "en" => %{posy: "Spring Posy", euc: "Eucalyptus Bunch", card: "Handwritten Card", choc: "Chocolates"}
}

locales = %{"sv" => "sv-FI", "fi" => "fi", "en" => "en-GB"}

gift = fn lang ->
  n = names[lang]

  [
    order_reference: "2026-00428",
    ordered_at: ~U[2026-05-13 11:32:00Z],
    fulfillment_method: :delivery,
    recipient_name: "Margareta Lindqvist",
    recipient_phone_number: "+358 40 555 0123",
    delivery_address: "Korsholmsesplanaden 12 A 4, 65100 Vasa",
    delivery_instructions:
      %{
        "sv" => "Ringklocka till översta våningen. Om ingen öppnar, lämna hos grannen.",
        "fi" => "Ovikello ylimpään kerrokseen. Jos kukaan ei avaa, jätä naapurille.",
        "en" => "Doorbell to the top floor. If nobody answers, leave it with the neighbour."
      }[lang],
    card_message:
      %{
        "sv" => "Grattis på födelsedagen, mamma! Med kärlek från oss alla.",
        "fi" => "Hyvää syntymäpäivää, äiti! Rakkaudella meiltä kaikilta.",
        "en" => "Happy birthday, Mum! With love from us all."
      }[lang],
    discount_rate: "0.10",
    fee: "9.00",
    line_items: [
      {n.posy, :medium, "39.90", 1, "0.255"},
      {n.euc, nil, "8.50", 2, "0.255"},
      {n.card, nil, "4.50", 1, "0.255"}
    ]
  ]
end

pickup = fn lang ->
  n = names[lang]

  [
    order_reference: "2026-00431",
    ordered_at: ~U[2026-05-13 13:08:00Z],
    fulfillment_method: :pickup,
    recipient_phone_number: "+358 40 555 0123",
    line_items: [{n.posy, :medium, "39.90", 1, "0.255"}, {n.euc, nil, "8.50", 1, "0.255"}]
  ]
end

fixtures =
  Enum.flat_map(locales, fn {lang, locale} ->
    [
      {"order.#{lang}.json", [locale: locale] ++ gift.(lang)},
      {"order.#{lang}.pickup.json", [locale: locale] ++ pickup.(lang)}
    ]
  end) ++
    [
      {"order.sv.nongift.json",
       [
         locale: "sv-FI",
         order_reference: "2026-00433",
         ordered_at: ~U[2026-05-13 11:32:00Z],
         fulfillment_method: :delivery,
         delivery_address: "Korsholmsesplanaden 12 A 4, 65100 Vasa",
         fee: "9.00",
         line_items: [{"Vårbukett", :medium, "39.90", 1, "0.255"}, {"Eukalyptusbukett", nil, "8.50", 2, "0.255"}]
       ]},
      {"order.sv.mixed-vat.json",
       [
         locale: "sv-FI",
         order_reference: "2026-00437",
         ordered_at: ~U[2026-05-13 11:32:00Z],
         fulfillment_method: :delivery,
         recipient_name: "Margareta Lindqvist",
         recipient_phone_number: "+358 40 555 0123",
         delivery_address: "Korsholmsesplanaden 12 A 4, 65100 Vasa",
         fee: "9.00",
         line_items: [{"Vårbukett", :medium, "39.90", 1, "0.255"}, {"Choklad", nil, "12.00", 1, "0.14"}]
       ]}
    ]

dir = Path.join([:code.priv_dir(:edenflowers), "receipts", "sample"])

for {file, opts} <- fixtures do
  json =
    opts
    |> build.()
    |> Receipt.build_payload()
    |> Jason.encode!(pretty: true)

  File.write!(Path.join(dir, file), json <> "\n")
  IO.puts("wrote #{file}")
end

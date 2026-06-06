# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Edenflowers.Repo.insert!(%Edenflowers.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Edenflowers.Accounts.User
alias Edenflowers.Actors
alias Edenflowers.Fulfillments
alias Edenflowers.Repo
alias Edenflowers.Store.ProductCategory
alias Edenflowers.Store.{TaxRate, FulfillmentOption, Product, ProductVariant, Promotion}
alias Edenflowers.Store.{Order, LineItem}
alias Edenflowers.Store.Order.Changes.GenerateOrderReference
alias Edenflowers.Weekday

require Ash.Query
alias Edenflowers.Expenses.Expense

# Admin user. `admin` is writable?: false on the resource so normal Ash actions
# can't set it — raw SQL is the appropriate escape hatch for seed setup.
admin_email = "mail@dmccrea.me"
admin_name = "David McCrea"

case Repo.query!("SELECT id FROM users WHERE email = $1", [admin_email]).rows do
  [] ->
    Ash.Seed.seed!(User, %{email: admin_email, name: admin_name, admin: true})

  [[_id]] ->
    Repo.query!("UPDATE users SET admin = true, name = $1 WHERE email = $2", [admin_name, admin_email])
end

tax_rate =
  TaxRate
  |> Ash.Changeset.for_create(:create, %{
    name: "Default",
    percentage: "0.255"
  })
  |> Ash.create!(authorize?: false)

FulfillmentOption
|> Ash.Changeset.for_create(:create, %{
  name: "Home delivery",
  sort_key: 0,
  fulfillment_method: :delivery,
  rate_type: :dynamic,
  minimum_cart_total: 0,
  base_price: "3.00",
  price_per_km: "1.50",
  free_dist_km: 5,
  max_dist_km: 20,
  tax_rate_id: tax_rate.id,
  available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]
})
|> Ash.create!(authorize?: false)

FulfillmentOption
|> Ash.Changeset.for_create(:create, %{
  name: "In store pickup",
  sort_key: 1,
  fulfillment_method: :pickup,
  rate_type: :fixed,
  base_price: "0.00",
  tax_rate_id: tax_rate.id
})
|> Ash.create!(authorize?: false)

# Create product categories
bouquets_category =
  ProductCategory
  |> Ash.Changeset.for_create(:create, %{
    name: "Bouquets",
    slug: "bouquets",
    visibility: :public,
    description: "Handcrafted floral arrangements featuring seasonal blooms in elegant compositions.",
    translations: %{
      "sv-FI": %{
        name: "Buketter",
        description: "Handgjorda blomsterarrangemang med säsongens blommor i eleganta kompositioner."
      },
      fi: %{
        name: "Kukkakimput",
        description: "Käsintehtyjä kukka-asetelmia sesongin kukista eleganteissa sommitelmissa."
      }
    }
  })
  |> Ash.create!(authorize?: false)

plants_category =
  ProductCategory
  |> Ash.Changeset.for_create(:create, %{
    name: "Plants",
    slug: "plants",
    visibility: :public,
    description: "Potted greenery and houseplants for the home, chosen for their character.",
    translations: %{
      "sv-FI": %{
        name: "Växter",
        description: "Krukväxter och grönska för hemmet, valda för sin karaktär."
      },
      fi: %{
        name: "Kasvit",
        description: "Ruukkukasveja ja viherkasveja kotiin, valittuna luonteensa mukaan."
      }
    }
  })
  |> Ash.create!(authorize?: false)

# Cards are surfaced only at checkout via ProductVariant.for_card_drawer.
# visibility: :hidden keeps the category out of the store ribbon while still
# allowing its products to be read by that action.
cards_category =
  ProductCategory
  |> Ash.Changeset.for_create(:create, %{
    name: "Cards",
    slug: "cards",
    visibility: :hidden,
    description: "Thoughtfully designed greeting cards for every occasion and sentiment.",
    translations: %{
      "sv-FI": %{
        name: "Kort",
        description: "Omsorgsfullt designade gratulationskort för varje tillfälle och känsla."
      },
      fi: %{
        name: "Kortit",
        description: "Huolellisesti suunniteltuja onnittelukortteja jokaiseen tilanteeseen."
      }
    }
  })
  |> Ash.create!(authorize?: false)

pre_loved_category =
  ProductCategory
  |> Ash.Changeset.for_create(:create, %{
    name: "Pre-Loved",
    slug: "pre-loved",
    visibility: :public,
    description: "Curated vintage and gently used items finding new homes and stories.",
    translations: %{
      "sv-FI": %{
        name: "Begagnat",
        description: "Utvalda vintage- och varsamt använda föremål som hittar nya hem och berättelser."
      },
      fi: %{
        name: "Käytetty",
        description: "Valittuja vintage- ja hellävaraisesti käytettyjä esineitä uusiin koteihin."
      }
    }
  })
  |> Ash.create!(authorize?: false)

# Create Bouquet products
for n <- 1..6 do
  product =
    Ash.Changeset.for_create(Product, :create, %{
      product_category_id: bouquets_category.id,
      tax_rate_id: tax_rate.id,
      name: "Bouquet #{n}",
      image_slug: "https://placehold.co/400x400",
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
      draft: false,
      featured: n <= 3
    })
    |> Ash.create!(authorize?: false)

  for size <- [:small, :medium, :large] do
    Ash.Changeset.for_create(ProductVariant, :create, %{
      product_id: product.id,
      price:
        "#{case size do
          :small -> 40
          :medium -> 50
          :large -> 60
        end}",
      size: size,
      image_slug: "https://placehold.co/400x400",
      stock_trackable: false,
      stock_quantity: 0,
      draft: false
    })
    |> Ash.create!(authorize?: false)
  end
end

# Create Plant products
for n <- 1..4 do
  product =
    Ash.Changeset.for_create(Product, :create, %{
      product_category_id: plants_category.id,
      tax_rate_id: tax_rate.id,
      name: "Plant #{n}",
      image_slug: "https://placehold.co/400x400",
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
      draft: false
    })
    |> Ash.create!(authorize?: false)

  for size <- [:small, :medium, :large] do
    Ash.Changeset.for_create(ProductVariant, :create, %{
      product_id: product.id,
      price:
        "#{case size do
          :small -> 18
          :medium -> 32
          :large -> 55
        end}",
      size: size,
      image_slug: "https://placehold.co/400x400",
      stock_trackable: false,
      stock_quantity: 0,
      draft: false
    })
    |> Ash.create!(authorize?: false)
  end
end

# Create Card products — category is draft, so they don't surface in the store
# ribbon, but they can still be added during checkout.
for n <- 1..4 do
  product =
    Ash.Changeset.for_create(Product, :create, %{
      product_category_id: cards_category.id,
      tax_rate_id: tax_rate.id,
      name: "Card #{n}",
      image_slug: "https://placehold.co/400x400",
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
      draft: false
    })
    |> Ash.create!(authorize?: false)

  for size <- [:small, :medium, :large] do
    Ash.Changeset.for_create(ProductVariant, :create, %{
      product_id: product.id,
      price:
        "#{case size do
          :small -> 5
          :medium -> 7
          :large -> 10
        end}",
      size: size,
      image_slug: "https://placehold.co/400x400",
      stock_trackable: false,
      stock_quantity: 0,
      draft: false
    })
    |> Ash.create!(authorize?: false)
  end
end

# Create Pre-Loved products
for n <- 1..3 do
  product =
    Ash.Changeset.for_create(Product, :create, %{
      product_category_id: pre_loved_category.id,
      tax_rate_id: tax_rate.id,
      name: "Pre-Loved Item #{n}",
      image_slug: "https://placehold.co/400x400",
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
      draft: false
    })
    |> Ash.create!(authorize?: false)

  for size <- [:small, :medium] do
    Ash.Changeset.for_create(ProductVariant, :create, %{
      product_id: product.id,
      price:
        "#{case size do
          :small -> 15
          :medium -> 25
        end}",
      size: size,
      image_slug: "https://placehold.co/400x400",
      stock_trackable: false,
      stock_quantity: 0,
      draft: false
    })
    |> Ash.create!(authorize?: false)
  end
end

Promotion
|> Ash.Changeset.for_create(
  :create,
  %{
    name: "Summer offer, 15% off",
    code: "SUMMER15",
    discount_rate: "0.15",
    minimum_cart_total: "30.00",
    start_date: nil,
    expiration_date: ~D[2099-07-01]
  }
)
|> Ash.create!(authorize?: false)

for {document_id, vendor, vat, date, total, vat_amount, currency, category, description, confidence} <- [
      {"doc-001", "Staples Finland Oy", "FI12345678", ~D[2026-01-08], "47.50", "9.69", :eur, :office_supplies,
       "Printer paper and pens", :high},
      {"doc-002", "Finnair Oyj", "FI23456789", ~D[2026-01-15], "312.00", "0.00", :eur, :travel,
       "Flight to Helsinki for supplier meeting", :high},
      {"doc-003", "Ravintola Faros", "FI34567890", ~D[2026-01-22], "68.40", "13.96", :eur, :meals, "Team lunch",
       :medium},
      {"doc-004", "Adobe Systems", nil, ~D[2026-02-01], "54.99", "0.00", :eur, :software,
       "Adobe Creative Cloud monthly subscription", :high},
      {"doc-005", "Vaasan Energia", "FI45678901", ~D[2026-02-10], "189.30", "38.63", :eur, :utilities,
       "Electricity bill — February", :high},
      {"doc-006", "Meta Platforms Ireland", nil, ~D[2026-02-14], "120.00", "0.00", :eur, :marketing,
       "Instagram ad campaign — Valentine's Day", :high},
      {"doc-007", "Tilitoimisto Laskenta Oy", "FI56789012", ~D[2026-02-28], "450.00", "91.85", :eur,
       :professional_services, "Monthly bookkeeping", :high},
      {"doc-008", "Tokmanni", "FI67890123", ~D[2026-03-05], "23.80", "4.86", :eur, :office_supplies,
       "Cleaning supplies", :medium},
      {"doc-009", "VR Group", "FI78901234", ~D[2026-03-12], "44.60", "0.00", :eur, :travel,
       "Train tickets Vaasa–Tampere", :high},
      {"doc-010", "Kotipizza", nil, ~D[2026-03-19], "31.50", "6.43", :eur, :meals, "Working lunch during stocktake",
       :low},
      {"doc-011", "Google Ireland Limited", nil, ~D[2026-04-01], "29.99", "0.00", :eur, :software,
       "Google Workspace monthly", :high},
      {"doc-012", "Pohjanmaan Kukkutukku", "FI89012345", ~D[2026-04-03], "875.00", "178.65", :eur, :other,
       "Bulk flower stock — spring delivery", :high},
      {"doc-013", "Elisa Oyj", "FI90123456", ~D[2026-04-07], "39.90", "8.15", :eur, :utilities,
       "Business mobile subscription", :high},
      {"doc-014", "Sanoma Media Finland", "FI01234567", ~D[2026-04-18], "600.00", "122.46", :eur, :marketing,
       "Print ad in local newspaper", :medium},
      {"doc-015", "Vaasan kaupunki", "FI11223344", ~D[2026-05-01], "210.00", "0.00", :eur, :other,
       "Annual business licence fee", :high}
    ] do
  Expense
  |> Ash.Changeset.for_create(:ingest, %{
    document_id: document_id,
    vendor_name: vendor,
    vendor_vat_number: vat,
    date: date,
    total_amount: total,
    vat_amount: vat_amount,
    currency: currency,
    category: category,
    description: description,
    confidence: confidence
  })
  |> Ash.create!(authorize?: false)
end

# Placed orders. Checkout drives orders through a state machine and seals them
# once placed, so normal Ash actions can't construct a finished order. Ash.Seed
# writes attributes directly, bypassing transitions and policies — the right
# escape hatch for fixtures, the same as the admin user above.
#
# Line item unit_price/tax_rate are snapshots; at checkout PopulateFromVariant
# copies them off the chosen variant. We mirror that here so the dashboard's
# subtotal/tax aggregates add up.
home_delivery =
  FulfillmentOption
  |> Ash.Query.filter(fulfillment_method == :delivery)
  |> Ash.read_first!(authorize?: false)

store_pickup =
  FulfillmentOption
  |> Ash.Query.filter(fulfillment_method == :pickup)
  |> Ash.read_first!(authorize?: false)

summer_promo =
  Promotion
  |> Ash.Query.filter(code == "SUMMER15")
  |> Ash.read_first!(authorize?: false)

# Pick a handful of variants to build carts from, loading the tax rate so we can
# snapshot it onto the line items.
variants =
  ProductVariant
  |> Ash.Query.load(product: [:tax_rate])
  |> Ash.read!(authorize?: false)

variant_for = fn product_name, size ->
  Enum.find(variants, fn v -> v.product.name == product_name and v.size == size end)
end

# Fulfillment dates are relative to whenever the seed runs. Future dates are
# resolved through the same availability rules as checkout, so running seeds on
# a Monday or after a same-day deadline cannot create an impossible order.
now = DateTime.now!("Europe/Helsinki")
today = DateTime.to_date(now)

fulfillment_date_for = fn option, days_out ->
  requested_date = Date.add(today, days_out)

  if days_out < 0 do
    Stream.iterate(requested_date, &Date.add(&1, -1))
    |> Enum.find(fn date ->
      date not in option.disabled_dates and
        (date in option.enabled_dates or Weekday.from_date(date) in option.available_days)
    end)
  else
    Stream.iterate(requested_date, &Date.add(&1, 1))
    |> Enum.find(fn date -> Fulfillments.fulfill_on_date(option, date, now) == :ok end)
  end
end

# Each order varies a different axis: fulfillment method, gift vs. not, a
# promotion, a larger multi-item cart, locales, and one already fulfilled so the
# dashboard's open/completed split has data on both sides.
orders = [
  %{
    customer_name: "Aino Virtanen",
    customer_email: "aino.virtanen@example.fi",
    fulfillment_option: home_delivery,
    fulfillment_date: today,
    recipient_name: "Aino Virtanen",
    recipient_phone_number: "+358 40 123 4567",
    delivery_address: "Gerbyntie 16, 65230 Vaasa",
    geocoded_address: "Gerbyvägen 16, 65230 Vasa",
    position: "63.1157,21.61864",
    here_id: "here:af:streetsection:olhtF0fcY2Tg2P7kFPBnMB:EAIaAjE2",
    distance: 1651,
    gift: false,
    locale: "fi",
    items: [{"Bouquet 1", :medium, 1}, {"Plant 2", :small, 1}]
  },
  %{
    customer_name: "Mikael Lindholm",
    customer_email: "mikael.lindholm@example.fi",
    fulfillment_option: home_delivery,
    fulfillment_date: today,
    recipient_name: "Sofia Lindholm",
    recipient_phone_number: "+358 50 987 6543",
    delivery_address: "Sundomintie 130, 65410 Sundom",
    geocoded_address: "Sundomvägen 130, 65410 Vasa",
    position: "63.03232,21.54662",
    here_id: "here:af:streetsection:DnEELU-r45CN9NK9d3YMnB:EAIaAzEzMA",
    distance: 12_711,
    gift: true,
    card_message: "Happy birthday, with love.",
    # A gift order carries a card: a line item flagged is_card, built from a
    # variant in the Cards category. Checkout enforces one card per order
    # (SwapCardLineItem), so at most one card entry here.
    card: {"Card 1", :medium},
    items: [{"Bouquet 3", :large, 1}]
  },
  %{
    customer_name: "Elina Korhonen",
    customer_email: "elina.korhonen@example.fi",
    fulfillment_option: store_pickup,
    days_out: 1,
    gift: false,
    items: [{"Plant 1", :medium, 2}, {"Bouquet 2", :small, 1}]
  },
  %{
    customer_name: "Johan Nyström",
    customer_email: "johan.nystrom@example.fi",
    fulfillment_option: home_delivery,
    days_out: 3,
    recipient_name: "Johan Nyström",
    recipient_phone_number: "+358 44 222 1188",
    delivery_address: "Västervikintie 17, 65280 Vaasa",
    geocoded_address: "Västerviksvägen 17, 65280 Vasa",
    position: "63.13433,21.59774",
    here_id: "here:af:streetsection:JsgM2SKLxD8mRXEtSARhmA:CgcIBCDIufx9EAEaAjE3",
    distance: 2254,
    gift: false,
    items: [{"Bouquet 4", :medium, 1}, {"Bouquet 5", :medium, 1}]
  },
  %{
    customer_name: "Liisa Mäkinen",
    customer_email: "liisa.makinen@example.fi",
    fulfillment_option: home_delivery,
    days_out: 4,
    recipient_name: "Liisa Mäkinen",
    recipient_phone_number: "+358 41 555 0099",
    delivery_address: "Vanhan Vaasan katu 20, 65370 Vaasa",
    geocoded_address: "Gamla Vasa gatan 20, 65370 Vasa",
    position: "63.08621,21.72555",
    here_id: "here:af:streetsection:HL-snKUH905p0HXizdKhkC:CgcIBCCayoF-EAEaAjIw",
    distance: 9273,
    gift: false,
    locale: "fi",
    # Cart total well above the promo's €30 minimum so the discount applies.
    promotion: summer_promo,
    items: [{"Bouquet 6", :large, 2}, {"Plant 3", :medium, 1}]
  },
  %{
    customer_name: "Erik Sundström",
    customer_email: "erik.sundstrom@example.fi",
    fulfillment_option: store_pickup,
    days_out: 5,
    # A gift order: checkout's submit_gift_options requires recipient_name when
    # gift is true, and a card message rides on a card line item. Mirror both so
    # this fixture matches an order that actually passed through checkout.
    gift: true,
    recipient_name: "Astrid Sundström",
    card_message: "Tack för allt!",
    card: {"Card 2", :medium},
    # A large mixed cart to exercise multi-line aggregates.
    items: [{"Bouquet 1", :large, 1}, {"Bouquet 4", :small, 2}, {"Plant 1", :large, 1}, {"Plant 4", :small, 1}]
  },
  %{
    customer_name: "Hanna Järvinen",
    customer_email: "hanna.jarvinen@example.fi",
    fulfillment_option: home_delivery,
    # Ordered a few days back and already delivered — lands in the dashboard's
    # completed side, not open orders. Both dates sit in the past, in order.
    ordered_at: DateTime.add(DateTime.utc_now(), -6, :day),
    days_out: -2,
    recipient_name: "Hanna Järvinen",
    recipient_phone_number: "+358 45 321 7654",
    delivery_address: "Rantamaantie 31, 65350 Vaasa",
    geocoded_address: "Strandvägen 31, 65350 Vasa",
    position: "63.07736,21.67323",
    here_id: "here:af:streetsection:KI1pyE5DUdLEue2Mt7LnjC:EAIaAjMx",
    distance: 7902,
    gift: false,
    fulfillment_status: :fulfilled,
    items: [{"Bouquet 2", :medium, 1}]
  }
]

for order_attrs <- orders do
  fulfillment_option = order_attrs.fulfillment_option
  promotion = order_attrs[:promotion]
  user = User.upsert!(order_attrs.customer_email, order_attrs.customer_name, actor: Actors.system_actor())

  {:ok, fulfillment_fee} =
    Fulfillments.calculate_price(fulfillment_option, order_attrs[:distance] || 0)

  order =
    Ash.Seed.seed!(Order, %{
      order_reference: GenerateOrderReference.generate(),
      state: :placed,
      payment_status: :paid,
      fulfillment_status: order_attrs[:fulfillment_status] || :pending,
      ordered_at: order_attrs[:ordered_at] || DateTime.utc_now(),
      customer_name: order_attrs.customer_name,
      customer_email: order_attrs.customer_email,
      user_id: user.id,
      gift: order_attrs.gift,
      card_message: order_attrs[:card_message],
      recipient_name: order_attrs[:recipient_name],
      recipient_phone_number: order_attrs[:recipient_phone_number],
      delivery_address: order_attrs[:delivery_address],
      geocoded_address: order_attrs[:geocoded_address],
      position: order_attrs[:position],
      here_id: order_attrs[:here_id],
      distance: order_attrs[:distance],
      fulfillment_date:
        order_attrs[:fulfillment_date] ||
          fulfillment_date_for.(fulfillment_option, order_attrs.days_out),
      fulfillment_option_id: fulfillment_option.id,
      fulfillment_option_name: fulfillment_option.name,
      fulfillment_method: fulfillment_option.fulfillment_method,
      fulfillment_fee: fulfillment_fee,
      fulfillment_tax_percentage: tax_rate.percentage,
      payment_intent_id: "pi_seed_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}",
      locale: order_attrs[:locale] || "sv-FI",
      # Snapshot the promotion the same way SnapshotPromotion does at checkout.
      # LineItem.discount keys off order.discount_rate + promotion_id, so both
      # the relationship and the frozen columns must be set for totals to match.
      promotion_id: promotion && promotion.id,
      discount_rate: promotion && promotion.discount_rate,
      promotion_name: promotion && promotion.name,
      promotion_code: promotion && to_string(promotion.code)
    })

  for {product_name, size, quantity} <- order_attrs.items do
    variant = variant_for.(product_name, size)

    Ash.Seed.seed!(LineItem, %{
      order_id: order.id,
      product_id: variant.product.id,
      product_variant_id: variant.id,
      quantity: quantity,
      unit_price: variant.price,
      tax_rate: variant.product.tax_rate.percentage,
      product_name: variant.product.name,
      product_image_slug: variant.image_slug,
      variant_size: variant.size,
      is_card: false
    })
  end

  if card = order_attrs[:card] do
    {card_name, card_size} = card
    card_variant = variant_for.(card_name, card_size)

    Ash.Seed.seed!(LineItem, %{
      order_id: order.id,
      product_id: card_variant.product.id,
      product_variant_id: card_variant.id,
      quantity: 1,
      unit_price: card_variant.price,
      tax_rate: card_variant.product.tax_rate.percentage,
      product_name: card_variant.product.name,
      product_image_slug: card_variant.image_slug,
      variant_size: card_variant.size,
      is_card: true
    })
  end
end

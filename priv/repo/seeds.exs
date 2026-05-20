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
alias Edenflowers.Store.ProductCategory
alias Edenflowers.Store.{TaxRate, FulfillmentOption, Product, ProductVariant, Promotion}

admin_email = "mail@dmccrea.me"
admin_name = "David McCrea"

Ash.Seed.seed!(User, %{email: admin_email, name: admin_name, admin: true})

tax_rate =
  TaxRate
  |> Ash.Changeset.for_create(:create, %{
    name: "Default",
    percentage: "0.255"
  })
  |> Ash.create!(authorize?: false)

delivery_option =
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

pickup_option =
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
bouquet_variant =
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

    variants =
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

    {product.name, variants}
  end
  |> then(fn [{name, variants} | _] -> {Enum.find(variants, &(&1.size == :medium)), name} end)

# Create Plant products
plant_variant =
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

    variants =
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

    {product.name, variants}
  end
  |> then(fn [{name, variants} | _] -> {Enum.find(variants, &(&1.size == :small)), name} end)

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

promotion =
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

alias Edenflowers.Store.{Order, LineItem}

admin_user = Ash.get!(User, [email: admin_email], authorize?: false)

# Helper to build a line item seed map; product_name is passed explicitly
# since variants created in-loop don't have the association loaded.
line_item_attrs = fn {variant, product_name}, order_id, quantity ->
  %{
    order_id: order_id,
    product_id: variant.product_id,
    product_variant_id: variant.id,
    unit_price: variant.price,
    tax_rate: Decimal.new("0.255"),
    product_name: product_name,
    product_image_slug: variant.image_slug,
    is_card: false,
    quantity: quantity
  }
end

# 1. Open order — pickup, single bouquet
order1 =
  Ash.Seed.seed!(Order, %{
    order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
    state: :placed,
    payment_status: :paid,
    fulfillment_status: :pending,
    fulfillment_method: :pickup,
    fulfillment_fee: Decimal.new("0.00"),
    fulfillment_tax_percentage: Decimal.new("0.255"),
    fulfillment_option_name: pickup_option.name,
    fulfillment_option_id: pickup_option.id,
    fulfillment_date: Date.add(Date.utc_today(), 3),
    customer_name: admin_name,
    customer_email: admin_email,
    recipient_name: admin_name,
    gift: false,
    ordered_at: DateTime.utc_now(),
    payment_intent_id: "pi_seed_001",
    user_id: admin_user.id
  })

Ash.Seed.seed!(LineItem, line_item_attrs.(bouquet_variant, order1.id, 1))

# 2. Open order — delivery, two items
order2 =
  Ash.Seed.seed!(Order, %{
    order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
    state: :placed,
    payment_status: :paid,
    fulfillment_status: :pending,
    fulfillment_method: :delivery,
    fulfillment_fee: Decimal.new("7.50"),
    fulfillment_tax_percentage: Decimal.new("0.255"),
    fulfillment_option_name: delivery_option.name,
    fulfillment_option_id: delivery_option.id,
    fulfillment_date: Date.add(Date.utc_today(), 5),
    customer_name: admin_name,
    customer_email: admin_email,
    recipient_name: "Anna Lindqvist",
    delivery_address: "Mannerheimintie 12, Helsinki",
    delivery_instructions: "Leave at the door",
    gift: false,
    ordered_at: DateTime.add(DateTime.utc_now(), -2, :day),
    payment_intent_id: "pi_seed_002",
    user_id: admin_user.id
  })

Ash.Seed.seed!(LineItem, line_item_attrs.(bouquet_variant, order2.id, 2))
Ash.Seed.seed!(LineItem, line_item_attrs.(plant_variant, order2.id, 1))

# 3. Open order — gift with card message, pickup
order3 =
  Ash.Seed.seed!(Order, %{
    order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
    state: :placed,
    payment_status: :paid,
    fulfillment_status: :pending,
    fulfillment_method: :pickup,
    fulfillment_fee: Decimal.new("0.00"),
    fulfillment_tax_percentage: Decimal.new("0.255"),
    fulfillment_option_name: pickup_option.name,
    fulfillment_option_id: pickup_option.id,
    fulfillment_date: Date.add(Date.utc_today(), 7),
    customer_name: admin_name,
    customer_email: admin_email,
    recipient_name: "Mia Korhonen",
    gift: true,
    card_message: "Happy birthday! Wishing you all the best.",
    ordered_at: DateTime.add(DateTime.utc_now(), -1, :day),
    payment_intent_id: "pi_seed_003",
    user_id: admin_user.id
  })

Ash.Seed.seed!(LineItem, line_item_attrs.(bouquet_variant, order3.id, 1))

# 4. Open order — delivery with promotion applied
order4 =
  Ash.Seed.seed!(Order, %{
    order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
    state: :placed,
    payment_status: :paid,
    fulfillment_status: :pending,
    fulfillment_method: :delivery,
    fulfillment_fee: Decimal.new("10.50"),
    fulfillment_tax_percentage: Decimal.new("0.255"),
    fulfillment_option_name: delivery_option.name,
    fulfillment_option_id: delivery_option.id,
    fulfillment_date: Date.add(Date.utc_today(), 2),
    customer_name: admin_name,
    customer_email: admin_email,
    recipient_name: "Erik Svensson",
    delivery_address: "Esplanadi 5, Helsinki",
    gift: false,
    promotion_id: promotion.id,
    promotion_name: promotion.name,
    promotion_code: promotion.code,
    discount_rate: promotion.discount_rate,
    ordered_at: DateTime.add(DateTime.utc_now(), -3, :day),
    payment_intent_id: "pi_seed_004",
    user_id: admin_user.id
  })

Ash.Seed.seed!(LineItem, line_item_attrs.(bouquet_variant, order4.id, 3))

# 5. Past order — fulfilled, pickup, single bouquet
order5 =
  Ash.Seed.seed!(Order, %{
    order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
    state: :placed,
    payment_status: :paid,
    fulfillment_status: :fulfilled,
    fulfillment_method: :pickup,
    fulfillment_fee: Decimal.new("0.00"),
    fulfillment_tax_percentage: Decimal.new("0.255"),
    fulfillment_option_name: pickup_option.name,
    fulfillment_option_id: pickup_option.id,
    fulfillment_date: Date.add(Date.utc_today(), -7),
    customer_name: admin_name,
    customer_email: admin_email,
    recipient_name: admin_name,
    gift: false,
    ordered_at: DateTime.add(DateTime.utc_now(), -10, :day),
    payment_intent_id: "pi_seed_005",
    user_id: admin_user.id
  })

Ash.Seed.seed!(LineItem, line_item_attrs.(bouquet_variant, order5.id, 1))

# 6. Past order — fulfilled, delivery, gift to recipient
order6 =
  Ash.Seed.seed!(Order, %{
    order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
    state: :placed,
    payment_status: :paid,
    fulfillment_status: :fulfilled,
    fulfillment_method: :delivery,
    fulfillment_fee: Decimal.new("9.00"),
    fulfillment_tax_percentage: Decimal.new("0.255"),
    fulfillment_option_name: delivery_option.name,
    fulfillment_option_id: delivery_option.id,
    fulfillment_date: Date.add(Date.utc_today(), -14),
    customer_name: admin_name,
    customer_email: admin_email,
    recipient_name: "Sofia Bergman",
    delivery_address: "Bulevardi 20, Helsinki",
    gift: true,
    card_message: "Thinking of you — with love.",
    ordered_at: DateTime.add(DateTime.utc_now(), -17, :day),
    payment_intent_id: "pi_seed_006",
    user_id: admin_user.id
  })

Ash.Seed.seed!(LineItem, line_item_attrs.(plant_variant, order6.id, 2))

# 7. Past order — fulfilled, with promotion, receipt emailed
order7 =
  Ash.Seed.seed!(Order, %{
    order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
    state: :placed,
    payment_status: :paid,
    fulfillment_status: :fulfilled,
    fulfillment_method: :pickup,
    fulfillment_fee: Decimal.new("0.00"),
    fulfillment_tax_percentage: Decimal.new("0.255"),
    fulfillment_option_name: pickup_option.name,
    fulfillment_option_id: pickup_option.id,
    fulfillment_date: Date.add(Date.utc_today(), -21),
    customer_name: admin_name,
    customer_email: admin_email,
    recipient_name: admin_name,
    gift: false,
    promotion_id: promotion.id,
    promotion_name: promotion.name,
    promotion_code: promotion.code,
    discount_rate: promotion.discount_rate,
    ordered_at: DateTime.add(DateTime.utc_now(), -24, :day),
    payment_intent_id: "pi_seed_007",
    receipt_emailed_at: DateTime.add(DateTime.utc_now(), -24, :day),
    receipt_sha256: "abc123seedhash",
    user_id: admin_user.id
  })

Ash.Seed.seed!(LineItem, line_item_attrs.(bouquet_variant, order7.id, 2))
Ash.Seed.seed!(LineItem, line_item_attrs.(plant_variant, order7.id, 1))

# 8. Past order — payment failed (edge case)
order8 =
  Ash.Seed.seed!(Order, %{
    order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
    state: :placed,
    payment_status: :failed,
    fulfillment_status: :fulfilled,
    fulfillment_method: :delivery,
    fulfillment_fee: Decimal.new("6.00"),
    fulfillment_tax_percentage: Decimal.new("0.255"),
    fulfillment_option_name: delivery_option.name,
    fulfillment_option_id: delivery_option.id,
    fulfillment_date: Date.add(Date.utc_today(), -30),
    customer_name: admin_name,
    customer_email: admin_email,
    recipient_name: "Lars Eriksson",
    delivery_address: "Fredrikinkatu 33, Helsinki",
    gift: false,
    ordered_at: DateTime.add(DateTime.utc_now(), -32, :day),
    payment_intent_id: "pi_seed_008",
    user_id: admin_user.id
  })

Ash.Seed.seed!(LineItem, line_item_attrs.(plant_variant, order8.id, 1))

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
alias Edenflowers.Repo
alias Edenflowers.Store.ProductCategory
alias Edenflowers.Store.{TaxRate, FulfillmentOption, Product, ProductVariant, Promotion}
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
  {"doc-001", "Staples Finland Oy", "FI12345678", ~D[2026-01-08], "47.50", "9.69", :eur, :office_supplies, "Printer paper and pens", :high},
  {"doc-002", "Finnair Oyj", "FI23456789", ~D[2026-01-15], "312.00", "0.00", :eur, :travel, "Flight to Helsinki for supplier meeting", :high},
  {"doc-003", "Ravintola Faros", "FI34567890", ~D[2026-01-22], "68.40", "13.96", :eur, :meals, "Team lunch", :medium},
  {"doc-004", "Adobe Systems", nil, ~D[2026-02-01], "54.99", "0.00", :eur, :software, "Adobe Creative Cloud monthly subscription", :high},
  {"doc-005", "Vaasan Energia", "FI45678901", ~D[2026-02-10], "189.30", "38.63", :eur, :utilities, "Electricity bill — February", :high},
  {"doc-006", "Meta Platforms Ireland", nil, ~D[2026-02-14], "120.00", "0.00", :eur, :marketing, "Instagram ad campaign — Valentine's Day", :high},
  {"doc-007", "Tilitoimisto Laskenta Oy", "FI56789012", ~D[2026-02-28], "450.00", "91.85", :eur, :professional_services, "Monthly bookkeeping", :high},
  {"doc-008", "Tokmanni", "FI67890123", ~D[2026-03-05], "23.80", "4.86", :eur, :office_supplies, "Cleaning supplies", :medium},
  {"doc-009", "VR Group", "FI78901234", ~D[2026-03-12], "44.60", "0.00", :eur, :travel, "Train tickets Vaasa–Tampere", :high},
  {"doc-010", "Kotipizza", nil, ~D[2026-03-19], "31.50", "6.43", :eur, :meals, "Working lunch during stocktake", :low},
  {"doc-011", "Google Ireland Limited", nil, ~D[2026-04-01], "29.99", "0.00", :eur, :software, "Google Workspace monthly", :high},
  {"doc-012", "Pohjanmaan Kukkutukku", "FI89012345", ~D[2026-04-03], "875.00", "178.65", :eur, :other, "Bulk flower stock — spring delivery", :high},
  {"doc-013", "Elisa Oyj", "FI90123456", ~D[2026-04-07], "39.90", "8.15", :eur, :utilities, "Business mobile subscription", :high},
  {"doc-014", "Sanoma Media Finland", "FI01234567", ~D[2026-04-18], "600.00", "122.46", :eur, :marketing, "Print ad in local newspaper", :medium},
  {"doc-015", "Vaasan kaupunki", "FI11223344", ~D[2026-05-01], "210.00", "0.00", :eur, :other, "Annual business licence fee", :high}
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

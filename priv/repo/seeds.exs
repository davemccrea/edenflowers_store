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

alias Edenflowers.Store.ProductCategory
alias Edenflowers.Store.{TaxRate, FulfillmentOption, Product, ProductVariant, Promotion}

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
  fulfillment_method: :delivery,
  rate_type: :dynamic,
  minimum_cart_total: 0,
  base_price: "3.00",
  price_per_km: "1.50",
  free_dist_km: 5,
  max_dist_km: 20,
  tax_rate_id: tax_rate.id,
  monday: false
})
|> Ash.create!(authorize?: false)

FulfillmentOption
|> Ash.Changeset.for_create(:create, %{
  name: "In store pickup",
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
    draft: false,
    description: "Handcrafted floral arrangements featuring seasonal blooms in elegant compositions.",
    translations: %{
      sv: %{
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

cards_category =
  ProductCategory
  |> Ash.Changeset.for_create(:create, %{
    name: "Cards",
    slug: "cards",
    draft: false,
    description: "Thoughtfully designed greeting cards for every occasion and sentiment.",
    translations: %{
      sv: %{
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
    draft: false,
    description: "Curated vintage and gently used items finding new homes and stories.",
    translations: %{
      sv: %{
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
      draft: false
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

# Create Card products
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

  # Cards have a single variant with fixed price
  Ash.Changeset.for_create(ProductVariant, :create, %{
    product_id: product.id,
    price: "5.00",
    size: :small,
    image_slug: "https://placehold.co/400x400",
    stock_trackable: false,
    stock_quantity: 0,
    draft: false
  })
  |> Ash.create!(authorize?: false)
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
    discount_percentage: "0.15",
    minimum_cart_total: "30.00",
    start_date: nil,
    expiration_date: ~D[2099-07-01]
  }
)
|> Ash.create!(authorize?: false)

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

alias Edenflowers.Accounts
alias Edenflowers.Accounts.User
alias Edenflowers.Actors
alias Edenflowers.Repo
alias Edenflowers.Catalog.ProductCategory
alias Edenflowers.Catalog.{Product, ProductVariant}
alias Edenflowers.Courses.{Course, CourseRegistration}
alias Edenflowers.Fulfillment.{Availability, Fee, FulfillmentOption, Weekday}
alias Edenflowers.Orders.{Order, LineItem, Payment}
alias Edenflowers.Orders.Calculations.Vat
alias Edenflowers.Pricing.{TaxRate, Promotion}
alias Edenflowers.Expenses.Expense

# Ash.Seed skips the actions, so draw from the same sequence they use.
next_reference = fn ->
  %{rows: [[reference]]} = Repo.query!("SELECT nextval('reference_seq')::text")
  reference
end

require Ash.Query

# Admin users. `admin` is writable?: false on the resource so normal Ash actions
# can't set it — raw SQL is the appropriate escape hatch for seed setup.
admins = [
  {"mail@dmccrea.me", "David McCrea"},
  {"info@edenflowers.fi", "Jennie McCrea"}
]

for {admin_email, admin_name} <- admins do
  case Repo.query!("SELECT id FROM users WHERE email = $1", [admin_email]).rows do
    [] ->
      Ash.Seed.seed!(User, %{email: admin_email, name: admin_name, admin: true})

    [[_id]] ->
      Repo.query!("UPDATE users SET admin = true, name = $1 WHERE email = $2", [admin_name, admin_email])
  end
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
      featured: n <= 3,
      free_delivery: n <= 2
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

subscription_product =
  Ash.Changeset.for_create(Product, :create, %{
    product_category_id: bouquets_category.id,
    tax_rate_id: tax_rate.id,
    name: "Florist's choice bouquet",
    image_slug: "https://placehold.co/400x400",
    description:
      "A florist's-choice bouquet of whatever is best that week. Buy one, or subscribe to have it delivered every one, two or four weeks.",
    translations: %{
      "sv-FI": %{
        name: "Floristens val",
        description:
          "En bukett av veckans finaste blommor, vald av floristen. Köp en, eller prenumerera och få den levererad varje, varannan eller var fjärde vecka."
      },
      fi: %{
        name: "Floristin valinta",
        description:
          "Floristin valitsema kimppu viikon parhaista kukista. Osta yksi tai tilaa se toimitettavaksi viikon, kahden tai neljän viikon välein."
      }
    },
    draft: false,
    featured: true,
    position: 0,
    free_delivery: true,
    subscribable: true
  })
  |> Ash.create!(authorize?: false)

for {size, price} <- [small: "45", medium: "60", large: "75"] do
  Ash.Changeset.for_create(ProductVariant, :create, %{
    product_id: subscription_product.id,
    price: price,
    size: size,
    image_slug: "https://placehold.co/400x400",
    stock_trackable: false,
    stock_quantity: 0,
    draft: false
  })
  |> Ash.create!(authorize?: false)
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

# One promotion per state the admin list tells apart: ended, not started yet,
# and used up (its one use is the overdue order below).
for attrs <- [
      %{
        name: "Valentine's, 20% off",
        code: "LOVE20",
        discount_rate: "0.20",
        minimum_cart_total: "40.00",
        start_date: Date.add(Date.utc_today(), -240),
        expiration_date: Date.add(Date.utc_today(), -225)
      },
      %{
        name: "Christmas, 10% off",
        code: "JUL10",
        discount_rate: "0.10",
        minimum_cart_total: "0.00",
        start_date: Date.add(Date.utc_today(), 50),
        expiration_date: Date.add(Date.utc_today(), 80)
      },
      %{
        name: "Mother's Day, one customer",
        code: "MOR10",
        discount_rate: "0.10",
        minimum_cart_total: "0.00",
        usage_limit: 1
      }
    ] do
  Promotion
  |> Ash.Changeset.for_create(:create, attrs)
  |> Ash.create!(authorize?: false)
end

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

# Dates are relative to today so a fresh seed always has courses open for
# booking, plus one that has already happened.
today = Date.utc_today()

[autumn_wreath, christmas_wreath, _table_arrangement, midsummer_crown] =
  [
    %{
      name: "Autumn Wreath Workshop",
      description:
        "Make a wreath for your front door from heather, rose hips, dried hydrangea and whatever the season " <>
          "has left in the forest. I provide the base, the materials and the tools; you take home a finished " <>
          "wreath. Coffee and something sweet included.",
      translations: %{
        "sv-FI": %{
          name: "Höstkranskurs",
          description:
            "Gör en krans till ytterdörren av ljung, nypon, torkad hortensia och det som finns kvar i skogen. " <>
              "Jag står för stomme, material och verktyg, du tar hem en färdig krans. Kaffe och något sött ingår."
        },
        fi: %{
          name: "Syyskranssikurssi",
          description:
            "Tee ulko-oveen kranssi kanervasta, ruusunmarjoista, kuivatusta hortensiasta ja metsän antimista. " <>
              "Minä tuon pohjan, materiaalit ja työkalut, sinä viet kotiin valmiin kranssin. Kahvi ja jotain makeaa kuuluu hintaan."
        }
      },
      date: Date.add(today, 18),
      start_time: ~T[10:00:00],
      end_time: ~T[13:00:00],
      register_before: Date.add(today, 11),
      total_places: 8,
      price: "75.00"
    },
    %{
      name: "Christmas Door Wreath",
      description:
        "An evening of spruce, pine, cones and ribbon. We bind a full evergreen wreath on a straw base that " <>
          "lasts well into January outdoors. Mulled juice and gingerbread while we work.",
      translations: %{
        "sv-FI": %{
          name: "Julkrans till dörren",
          description:
            "En kväll med gran, tall, kottar och band. Vi binder en tät vintergrön krans på halmstomme som håller " <>
              "långt in i januari utomhus. Glögg och pepparkakor medan vi jobbar."
        },
        fi: %{
          name: "Joulukranssi oveen",
          description:
            "Ilta kuusen, männyn, käpyjen ja nauhojen parissa. Sidomme tuuhean havukranssin olkipohjalle, ja se " <>
              "kestää ulkona pitkälle tammikuuhun. Glögiä ja pipareita työskennellessä."
        }
      },
      date: Date.add(today, 64),
      start_time: ~T[17:30:00],
      end_time: ~T[20:30:00],
      register_before: Date.add(today, 57),
      total_places: 10,
      price: "85.00"
    },
    %{
      name: "Christmas Table Arrangement",
      description:
        "A low arrangement for the Christmas table in a bowl of your choosing, with amaryllis, hyacinth, moss " <>
          "and evergreens. I'll show you how to keep it fresh through the holidays.",
      translations: %{
        "sv-FI": %{
          name: "Juldekoration till bordet",
          description:
            "Ett lågt arrangemang för julbordet i en skål du väljer själv, med amaryllis, hyacint, mossa och " <>
              "vintergröna kvistar. Jag visar hur du håller det fräscht över helgerna."
        },
        fi: %{
          name: "Joulupöydän asetelma",
          description:
            "Matala asetelma joulupöytään itse valitsemaasi kulhoon: amaryllista, hyasinttia, sammalta ja havuja. " <>
              "Näytän, miten pidät sen raikkaana pyhien yli."
        }
      },
      date: Date.add(today, 78),
      start_time: ~T[17:30:00],
      end_time: ~T[20:00:00],
      register_before: Date.add(today, 71),
      total_places: 10,
      price: "80.00"
    },
    %{
      name: "Midsummer Flower Crown",
      description:
        "Bind a crown from meadow flowers and garden greenery, in time for midsummer eve. Suitable for " <>
          "beginners and children from ten years old with an adult.",
      translations: %{
        "sv-FI": %{
          name: "Midsommarkrans",
          description:
            "Bind en krans av ängsblommor och grönt från trädgården, lagom till midsommarafton. Passar nybörjare " <>
              "och barn från tio år tillsammans med en vuxen."
        },
        fi: %{
          name: "Juhannusseppele",
          description:
            "Sido seppele niittykukista ja puutarhan vihreästä juhannusaatoksi. Sopii aloittelijoille ja " <>
              "yli kymmenvuotiaille lapsille aikuisen kanssa."
        }
      },
      date: Date.add(today, -90),
      start_time: ~T[13:00:00],
      end_time: ~T[15:00:00],
      register_before: Date.add(today, -97),
      total_places: 12,
      price: "45.00"
    }
  ]
  |> Enum.map(fn attrs ->
    Course
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{
        location_name: "Minimossen",
        location_address: "Myrvägen 1, 65230 Vasa",
        image_slug: "https://placehold.co/1000x1250",
        tax_rate_id: tax_rate.id
      })
    )
    |> Ash.create!(authorize?: false)
  end)

# Course bookings. Ash.Seed for the same reason as orders below: a booking is
# confirmed by a Stripe payment or by Jennie. The pending and cancelled ones should not
# show on the admin courses page. Emma and Kristina were added by Jennie and
# pay at the course, so they have no payment intent; Kristina already has.
# The third course is left empty on purpose, and the past one has its history.
[
  {autumn_wreath, "Anna Svensson", "anna.svensson@example.com", 3, :confirmed, "sv-FI", :stripe},
  {autumn_wreath, "Mikael Berg", "mikael.berg@example.com", 1, :confirmed, "sv-FI", :stripe},
  {autumn_wreath, "Laura Virtanen", "laura.virtanen@example.com", 2, :confirmed, "fi", :stripe},
  {autumn_wreath, "Emma Nyström", "emma.nystrom@example.com", 1, :confirmed, "sv-FI", :direct},
  {autumn_wreath, "Kristina Ahlroos", "kristina.ahlroos@example.com", 2, :confirmed, "sv-FI", :direct_paid},
  {autumn_wreath, "Johan Lindqvist", "johan.lindqvist@example.com", 1, :cancelled, "sv-FI", :stripe},
  {christmas_wreath, "Sofia Korhonen", "sofia.korhonen@example.com", 2, :confirmed, "fi", :stripe},
  {christmas_wreath, "Sarah Mitchell", "sarah.mitchell@example.com", 1, :confirmed, "en-GB", :stripe},
  {christmas_wreath, "Pekka Mäkinen", "pekka.makinen@example.com", 1, :pending, "fi", :stripe},
  {midsummer_crown, "Ida Westerlund", "ida.westerlund@example.com", 2, :confirmed, "sv-FI", :stripe},
  {midsummer_crown, "Matti Laine", "matti.laine@example.com", 1, :confirmed, "fi", :direct_paid}
]
|> Enum.each(fn {course, name, email, seats, status, locale, paid_via} ->
  Ash.Seed.seed!(CourseRegistration, %{
    course_id: course.id,
    name: name,
    email: email,
    seats: seats,
    status: status,
    locale: locale,
    reference: next_reference.(),
    tax_rate: tax_rate.percentage,
    amount: Decimal.mult(course.price, seats),
    confirmed_at: if(status == :confirmed, do: DateTime.utc_now()),
    # Already emailed, otherwise the SendConfirmationEmail trigger emails every
    # seeded booking — for real on staging.
    confirmation_emailed_at: if(status == :confirmed, do: DateTime.utc_now()),
    paid_at: if(paid_via == :direct_paid, do: DateTime.utc_now()),
    # A pending registration with a fake PaymentIntent makes the ReconcilePayment
    # cron fail against Stripe, so it stays an abandoned checkout instead.
    payment_intent_id:
      if(paid_via == :stripe and status != :pending,
        do: "pi_seed_#{System.unique_integer([:positive])}"
      )
  })
end)

# One of Anna's group of three dropped out.
CourseRegistration
|> Ash.Query.filter(email == "anna.svensson@example.com")
|> Ash.read_one!(authorize?: false)
|> Edenflowers.Courses.remove_registration_seat!(authorize?: false)

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

promotion_by_code = fn code ->
  Promotion
  |> Ash.Query.filter(code == ^code)
  |> Ash.read_first!(authorize?: false)
end

summer_promo = promotion_by_code.("SUMMER15")

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
    |> Enum.find(fn date -> Availability.unavailable_reason(option, date, now) == nil end)
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
    recipient_phone_number: "040 1234567",
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
    recipient_phone_number: "050 9876543",
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
    recipient_phone_number: "044 2221188",
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
    recipient_phone_number: "041 5550099",
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
    recipient_phone_number: "045 3217654",
    delivery_address: "Rantamaantie 31, 65350 Vaasa",
    geocoded_address: "Strandvägen 31, 65350 Vasa",
    position: "63.07736,21.67323",
    here_id: "here:af:streetsection:KI1pyE5DUdLEue2Mt7LnjC:EAIaAjMx",
    distance: 7902,
    gift: false,
    fulfillment_status: :fulfilled,
    items: [{"Bouquet 2", :medium, 1}]
  },
  %{
    # Paid, but its pickup day has passed without Jennie marking it collected.
    customer_name: "Tuula Rantanen",
    customer_email: "tuula.rantanen@example.fi",
    fulfillment_option: store_pickup,
    ordered_at: DateTime.add(DateTime.utc_now(), -4, :day),
    days_out: -1,
    gift: false,
    locale: "fi",
    promotion: promotion_by_code.("MOR10"),
    items: [{"Bouquet 6", :medium, 1}]
  },
  # The three below are changed after placing, further down.
  %{
    customer_name: "Petra Holm",
    customer_email: "petra.holm@example.fi",
    fulfillment_option: store_pickup,
    days_out: 2,
    gift: false,
    items: [{"Bouquet 3", :small, 1}]
  },
  %{
    customer_name: "Oskar Wikström",
    customer_email: "oskar.wikstrom@example.fi",
    fulfillment_option: store_pickup,
    days_out: 3,
    gift: false,
    locale: "en-GB",
    items: [{"Plant 4", :large, 1}]
  },
  %{
    customer_name: "Nora Back",
    customer_email: "nora.back@example.fi",
    fulfillment_option: store_pickup,
    days_out: 4,
    gift: false,
    items: [{"Bouquet 5", :small, 1}, {"Plant 2", :medium, 1}]
  }
]

for order_attrs <- orders do
  fulfillment_option = order_attrs.fulfillment_option
  promotion = order_attrs[:promotion]
  user = Accounts.upsert_user!(order_attrs.customer_email, order_attrs.customer_name, actor: Actors.system_actor())

  %{error: nil} = fee = Fee.calculate(fulfillment_option, order_attrs[:distance] || 0)

  order =
    Ash.Seed.seed!(Order, %{
      order_reference: next_reference.(),
      state: :placed,
      fulfillment_status: order_attrs[:fulfillment_status] || :pending,
      # Already emailed, otherwise the SendConfirmationEmail and SendDeliveredEmail
      # triggers email every seeded customer — for real on staging.
      receipt_emailed_at: DateTime.utc_now(),
      delivered_emailed_at: if(order_attrs[:fulfillment_status] == :fulfilled, do: DateTime.utc_now()),
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
      quoted_fulfillment_fee: fee.fulfillment_fee,
      in_free_delivery_zone: fee.in_free_delivery_zone,
      fulfillment_tax_rate: tax_rate.percentage,
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

  # Snapshot the VAT breakdown the same way SnapshotVatBreakdown does at checkout.
  # Clearing state makes Vat.breakdown compute from the line items rather than
  # read the snapshot this is about to write.
  order = Ash.load!(order, [:grand_total | Vat.load(nil, nil, nil)], authorize?: false)

  Ash.Seed.update!(order, %{
    vat_breakdown: Vat.breakdown(%{order | state: nil}),
    payment_intent_id: nil
  })

  Ash.Seed.seed!(Payment, %{
    order_id: order.id,
    amount: order.grand_total,
    method: :stripe,
    payment_intent_id: order.payment_intent_id,
    paid_at: order.ordered_at
  })
end

# Subscriptions, one per state the admin list and account page show, each with
# the order that started it and some with later deliveries (Occurrences).
# Ash.Seed for the same reason as the orders above. As in the app, the schedule
# runs on whole intervals from the first order's date: each Occurrence is the
# next date on it, and next_fulfillment_date the one after the latest. Active
# next dates sit beyond the lead time and the change cutoff, so the hourly
# occurrence job doesn't try to charge the fake Stripe ids in dev, and
# customers can still change them.
# Every email is marked sent, for the same reason as above.
alias Edenflowers.Orders.Subscription

weekly_bouquet = fn size -> variant_for.("Florist's choice bouquet", size) end

seed_subscription_order = fn subscription, user, attrs ->
  variant = weekly_bouquet.(attrs.size)
  %{error: nil} = fee = Fee.calculate(home_delivery, 1651)
  paid? = Map.get(attrs, :paid?, true)

  order =
    Ash.Seed.seed!(Order, %{
      order_reference: next_reference.(),
      state: :placed,
      origin: attrs.origin,
      subscription_id: subscription.id,
      subscription_date: attrs[:subscription_date],
      fulfillment_status: attrs[:fulfillment_status] || :pending,
      receipt_emailed_at: DateTime.utc_now(),
      details_emailed_at: if(not paid?, do: DateTime.utc_now()),
      delivered_emailed_at: if(attrs[:fulfillment_status] == :fulfilled, do: DateTime.utc_now()),
      ordered_at: DateTime.utc_now(),
      customer_name: user.name,
      customer_email: to_string(user.email),
      user_id: user.id,
      gift: subscription.recipient_name != user.name,
      card_message: attrs[:card_message],
      recipient_name: subscription.recipient_name,
      recipient_phone_number: subscription.recipient_phone_number,
      delivery_address: subscription.delivery_address,
      geocoded_address: "Gerbyvägen 16, 65230 Vasa",
      position: "63.1157,21.61864",
      here_id: "here:af:streetsection:olhtF0fcY2Tg2P7kFPBnMB:EAIaAjE2",
      distance: 1651,
      fulfillment_date: attrs.fulfillment_date,
      fulfillment_option_id: home_delivery.id,
      fulfillment_option_name: home_delivery.name,
      fulfillment_method: :delivery,
      quoted_fulfillment_fee: fee.fulfillment_fee,
      in_free_delivery_zone: fee.in_free_delivery_zone,
      fulfillment_tax_rate: tax_rate.percentage,
      payment_link_token: if(not paid?, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)),
      stripe_customer_id: if(attrs.origin == :online, do: subscription.stripe_customer_id),
      stripe_payment_method_id: if(attrs.origin == :online, do: subscription.stripe_payment_method_id),
      locale: subscription.locale
    })

  Ash.Seed.seed!(LineItem, %{
    order_id: order.id,
    product_id: variant.product.id,
    product_variant_id: variant.id,
    quantity: 1,
    unit_price: variant.price,
    tax_rate: variant.product.tax_rate.percentage,
    product_name: variant.product.name,
    product_image_slug: variant.image_slug,
    variant_size: variant.size,
    free_delivery: true,
    # Only the order that started the subscription carries the interval; an
    # Occurrence's line is a one-off.
    interval_weeks: if(attrs.origin == :online, do: subscription.interval_weeks),
    is_card: false
  })

  order = Ash.load!(order, [:grand_total | Vat.load(nil, nil, nil)], authorize?: false)
  Ash.Seed.update!(order, %{vat_breakdown: Vat.breakdown(%{order | state: nil})})

  if paid? do
    Ash.Seed.seed!(Payment, %{
      order_id: order.id,
      amount: order.grand_total,
      method: :stripe,
      payment_intent_id: "pi_seed_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}",
      paid_at: order.ordered_at
    })
  end

  order
end

subscriptions = [
  # David's own, so the account page has one to try pause and change on.
  %{
    email: "mail@dmccrea.me",
    name: "David McCrea",
    state: :active,
    size: :medium,
    interval_weeks: 1,
    first_days_out: -7,
    recipient_name: "David McCrea",
    locale: "sv-FI",
    occurrences: [%{fulfillment_status: :fulfilled}]
  },
  # A gift every two weeks.
  %{
    email: "helena.nyman@example.fi",
    name: "Helena Nyman",
    state: :active,
    size: :large,
    interval_weeks: 2,
    first_days_out: -15,
    recipient_name: "Ingrid Nyman",
    card_message: "Lots of love from Helena",
    locale: "sv-FI",
    occurrences: [%{fulfillment_status: :fulfilled}]
  },
  # Paused before its second delivery was charged, so its next date stays put
  # until it resumes.
  %{
    email: "otto.makinen@example.fi",
    name: "Otto Mäkinen",
    state: :paused,
    size: :small,
    interval_weeks: 4,
    first_days_out: -28,
    recipient_name: "Otto Mäkinen",
    locale: "fi",
    occurrences: []
  },
  # The card was refused for the latest delivery, which is placed unpaid with a
  # payment link; the subscription waits until it is paid.
  %{
    email: "sara.holm@example.fi",
    name: "Sara Holm",
    state: :payment_failed,
    size: :medium,
    interval_weeks: 1,
    first_days_out: -10,
    recipient_name: "Sara Holm",
    locale: "en",
    occurrences: [%{fulfillment_status: :fulfilled}, %{paid?: false}]
  },
  %{
    email: "jonas.berg@example.fi",
    name: "Jonas Berg",
    state: :cancelled,
    size: :medium,
    interval_weeks: 2,
    first_days_out: -21,
    recipient_name: "Jonas Berg",
    locale: "sv-FI",
    occurrences: [%{fulfillment_status: :fulfilled}]
  }
]

for attrs <- subscriptions do
  user = Accounts.upsert_user!(attrs.email, attrs.name, actor: Actors.system_actor())
  first_date = fulfillment_date_for.(home_delivery, attrs.first_days_out)
  scheduled_date = fn n -> Date.add(first_date, n * attrs.interval_weeks * 7) end

  subscription =
    Ash.Seed.seed!(Subscription, %{
      user_id: user.id,
      product_variant_id: weekly_bouquet.(attrs.size).id,
      fulfillment_option_id: home_delivery.id,
      state: attrs.state,
      interval_weeks: attrs.interval_weeks,
      next_fulfillment_date: scheduled_date.(length(attrs.occurrences) + 1),
      recipient_name: attrs.recipient_name,
      recipient_phone_number: "040 1234567",
      delivery_address: "Gerbyntie 16, 65230 Vaasa",
      card_message: attrs[:card_message],
      locale: attrs.locale,
      stripe_customer_id: "cus_seed_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}",
      stripe_payment_method_id: "pm_seed_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}",
      card_brand: "visa",
      card_last4: "4242",
      card_exp_month: 8,
      card_exp_year: 2028,
      setup_emailed_at: DateTime.utc_now()
    })

  seed_subscription_order.(subscription, user, %{
    origin: :online,
    size: attrs.size,
    fulfillment_date: first_date,
    fulfillment_status: :fulfilled,
    card_message: attrs[:card_message]
  })

  for {occurrence, n} <- Enum.with_index(attrs.occurrences, 1) do
    seed_subscription_order.(subscription, user, %{
      origin: :subscription,
      size: attrs.size,
      subscription_date: scheduled_date.(n),
      fulfillment_date: scheduled_date.(n),
      fulfillment_status: occurrence[:fulfillment_status],
      paid?: Map.get(occurrence, :paid?, true)
    })
  end
end

# Custom orders, payments and edits. Unlike the orders above, these go through
# the real actions as Jennie, so the order log, the payment rows, balances and
# payment links come out exactly as the app makes them. All pickups, so no
# address is geocoded, and nothing calls Stripe. Every customer email is marked
# as already sent, for the same reason as above.
alias Edenflowers.Orders
alias Edenflowers.Payments

jennie =
  User
  |> Ash.Query.filter(email == "info@edenflowers.fi")
  |> Ash.read_one!(authorize?: false)

custom_line = fn description, unit_price ->
  %{
    "kind" => "custom",
    "description" => description,
    "unit_price" => unit_price,
    "tax_rate_id" => tax_rate.id,
    "quantity" => "1"
  }
end

catalogue_line = fn product_name, size, quantity ->
  %{
    "kind" => "catalogue",
    "product_variant_id" => variant_for.(product_name, size).id,
    "quantity" => to_string(quantity)
  }
end

place_custom = fn attrs ->
  Map.merge(
    %{
      locale: "sv-FI",
      fulfillment_option_id: store_pickup.id,
      fulfillment_date: fulfillment_date_for.(store_pickup, attrs[:days_out] || 2),
      email_customer?: false
    },
    Map.delete(attrs, :days_out)
  )
  |> Orders.place_custom_order!(actor: jennie)
end

mark_emailed = fn order -> Ash.Seed.update!(order, %{receipt_emailed_at: DateTime.utc_now()}) end

# A Stripe payment arriving through the payment link, as the webhook would record it.
pay_by_link = fn order, payment_intent_id ->
  order = Orders.get_order_for_admin!(order.id, actor: jennie)
  Ash.Seed.update!(order, %{payment_intent_id: payment_intent_id})

  {:ok, :completed} =
    Payments.complete(%{
      id: payment_intent_id,
      metadata: %{"order_id" => order.id},
      amount_received: Edenflowers.External.StripeAPI.to_stripe_amount(order.balance)
    })

  mark_emailed.(Orders.get_order_for_admin!(order.id, actor: jennie))
end

# Phoned in for a funeral: no email, so Jennie copies the payment link into a text message.
place_custom.(%{
  customer_name: "Margareta Holm",
  customer_phone_number: "040 7654321",
  recipient_name: "Funeral of Gunnar Holm",
  card_message: "Tack för allt, vila i frid.",
  florist_note: "White roses and lilies only. The funeral home collects at 10:00, service at 11:00.",
  line_items: [custom_line.("Funeral spray, white roses and lilies", "120.00"), catalogue_line.("Card 3", :large, 1)]
})

# A walk-in who paid with MobilePay at the counter.
walk_in =
  place_custom.(%{
    customer_name: "Kalle Nieminen",
    customer_phone_number: "050 1239876",
    locale: "fi",
    days_out: 1,
    payment_link?: false,
    line_items: [catalogue_line.("Bouquet 2", :medium, 1), custom_line.("Extra eucalyptus", "8.00")]
  })

walk_in = Orders.get_order_for_admin!(walk_in.id, actor: jennie)
Orders.record_in_person_payment!(walk_in, walk_in.balance, :mobilepay, actor: jennie)

# Paid through the link, then made smaller, then refunded in the Stripe dashboard.
smaller =
  place_custom.(%{
    customer_name: "Sara Björk",
    customer_email: "sara.bjork@example.fi",
    days_out: 3,
    line_items: [catalogue_line.("Bouquet 5", :large, 2), custom_line.("Hand-tied ribbon", "6.00")]
  })

pay_by_link.(smaller, "pi_seed_smaller")
smaller = Orders.get_order_for_admin!(smaller.id, actor: jennie, load: [:line_items])
[bouquets | _] = Enum.filter(smaller.line_items, &(&1.product_variant_id != nil))

Orders.edit_order!(
  smaller,
  %{
    line_items: [
      %{"kind" => "catalogue", "id" => bouquets.id, "quantity" => "1"},
      custom_line.("Hand-tied ribbon", "6.00")
    ]
  },
  actor: jennie
)

{:ok, :recorded} =
  Payments.record_refund(%{id: "re_seed_smaller", payment_intent: "pi_seed_smaller", amount: 6000, status: "succeeded"})

# Delivered to a phone-only customer who promised to pay next week.
fulfilled_unpaid =
  place_custom.(%{
    customer_name: "Bertil Ek",
    customer_phone_number: "044 2223344",
    days_out: 0,
    line_items: [catalogue_line.("Bouquet 1", :small, 1)]
  })

Orders.mark_order_fulfilled!(fulfilled_unpaid, actor: jennie)

# Called off before it was paid.
cancelled =
  place_custom.(%{
    customer_name: "Ulla Granqvist",
    customer_phone_number: "045 6781122",
    days_out: 4,
    florist_note: "Cancelled: the family ordered elsewhere.",
    line_items: [custom_line.("Table arrangement for 8", "75.00")]
  })

Orders.cancel_order!(cancelled, actor: jennie)

# An online order the customer asked to add to by email after paying: it now
# has a balance to collect and a payment link for just that.
erik =
  Order
  |> Ash.Query.filter(customer_name == "Erik Sundström")
  |> Ash.Query.load(:line_items)
  |> Ash.read_one!(authorize?: false)

kept_lines = Enum.map(erik.line_items, &%{"kind" => "catalogue", "id" => &1.id, "quantity" => to_string(&1.quantity)})

Orders.edit_order!(erik, %{line_items: kept_lines ++ [catalogue_line.("Plant 2", :small, 1)]}, actor: jennie)
Orders.open_payment_link!(erik, actor: jennie)

# A custom order paid in part by link, the rest still owed.
part_paid =
  place_custom.(%{
    customer_name: "Johanna Lind",
    customer_email: "johanna.lind@example.fi",
    locale: "en-GB",
    days_out: 6,
    line_items: [catalogue_line.("Bouquet 3", :medium, 1)]
  })

pay_by_link.(part_paid, "pi_seed_part_paid")
part_paid = Orders.get_order_for_admin!(part_paid.id, actor: jennie, load: [:line_items])
[bouquet] = part_paid.line_items

Orders.edit_order!(
  part_paid,
  %{
    line_items: [
      %{"kind" => "catalogue", "id" => bouquet.id, "quantity" => "1"},
      custom_line.("Vase, hand-thrown", "35.00")
    ]
  },
  actor: jennie
)

online_order = fn customer_name ->
  Order
  |> Ash.Query.filter(customer_name == ^customer_name)
  |> Ash.Query.load([:grand_total, :line_items, :payments])
  |> Ash.read_one!(authorize?: false)
end

refund_in_full = fn order ->
  [payment] = order.payments

  {:ok, :recorded} =
    Payments.record_refund(%{
      id: "re_seed_#{order.order_reference}",
      payment_intent: payment.payment_intent_id,
      amount: Edenflowers.External.StripeAPI.to_stripe_amount(payment.amount),
      status: "succeeded"
    })
end

# Called off and refunded in full in the Stripe dashboard.
petra = online_order.("Petra Holm")
Orders.cancel_order!(petra, actor: jennie)
refund_in_full.(petra)

# Called off, but Jennie hasn't refunded it yet.
Orders.cancel_order!(online_order.("Oskar Wikström"), actor: jennie)

# Paid, then the plant was out of stock: money to hand back through Stripe.
nora = online_order.("Nora Back")
[bouquet | _] = Enum.filter(nora.line_items, &(&1.product_name == "Bouquet 5"))

Orders.edit_order!(nora, %{line_items: [%{"kind" => "catalogue", "id" => bouquet.id, "quantity" => "1"}]},
  actor: jennie
)

# Paid in cash, then the gift wrap was left off: money to hand back in person.
cash =
  place_custom.(%{
    customer_name: "Greta Lund",
    customer_phone_number: "040 5557788",
    days_out: 2,
    payment_link?: false,
    line_items: [catalogue_line.("Bouquet 4", :medium, 1), custom_line.("Gift wrapping", "5.00")]
  })

cash = Orders.get_order_for_admin!(cash.id, actor: jennie, load: [:line_items])
[bouquet | _] = Enum.filter(cash.line_items, &(&1.product_variant_id != nil))
cash = Orders.record_in_person_payment!(cash, cash.balance, :cash, actor: jennie)

Orders.edit_order!(cash, %{line_items: [%{"kind" => "catalogue", "id" => bouquet.id, "quantity" => "1"}]},
  actor: jennie
)

# Collected and paid by card at the counter.
collected =
  place_custom.(%{
    customer_name: "Henrik Ström",
    customer_phone_number: "050 4443322",
    locale: "fi",
    days_out: 0,
    payment_link?: false,
    line_items: [catalogue_line.("Plant 3", :large, 1)]
  })

collected = Orders.get_order_for_admin!(collected.id, actor: jennie)
collected = Orders.record_in_person_payment!(collected, collected.balance, :zettle, actor: jennie)
Orders.mark_order_fulfilled!(collected, actor: jennie)

# A free replacement for a returning customer whose first bouquet wilted.
place_custom.(%{
  customer_name: "Aino Virtanen",
  customer_email: "aino.virtanen@example.fi",
  locale: "fi",
  days_out: 1,
  payment_link?: false,
  florist_note: "Replaces her earlier delivery, which wilted the next day.",
  line_items: [custom_line.("Replacement bouquet", "0.00")]
})

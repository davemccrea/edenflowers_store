# Dev fixtures, built on the production base seed. Run it with:
#
#     just seed-db
#
# One example of each feature or variation the store and admin show. Add a new
# fixture only when it shows something none of the existing ones do.

alias Edenflowers.Accounts
alias Edenflowers.Accounts.User
alias Edenflowers.Actors
alias Edenflowers.Repo
alias Edenflowers.Catalog.ProductCategory
alias Edenflowers.Catalog.{Product, ProductVariant}
alias Edenflowers.Courses.{Course, CourseRegistration}
alias Edenflowers.Fulfillment.{Availability, Fee, FulfillmentOption, Weekday}
alias Edenflowers.Orders.{Order, LineItem}
alias Edenflowers.Payments.Payment
alias Edenflowers.Orders.Calculations.Vat
alias Edenflowers.Pricing.{TaxRate, Promotion}
alias Edenflowers.Expenses.Expense

alias Edenflowers.External.StripeAPI

require Ash.Query

# With `just seed-db --stripe`, every seeded Stripe payment, refund and
# subscription customer is created in Stripe test mode. Without it, nothing
# calls Stripe and the ids are made up. Stripe can't backdate, so its objects
# are all dated the day of seeding while the seeded payments keep their
# relative dates: the monthly report's Stripe sheet only matches this month.
seed_stripe? = Process.get(:seed_stripe, false)

if seed_stripe? and not String.starts_with?(Application.fetch_env!(:stripity_stripe, :api_key), "sk_test_") do
  raise "Seeding with Stripe needs a test-mode key (sk_test_…). Nothing was written."
end

# Returns the PaymentIntent, real and confirmed with Stripe's test card for
# the brand, or a made-up one with the same fields.
seed_payment_intent = fn amount, card_brand, metadata ->
  cents = StripeAPI.to_stripe_amount(amount)

  if seed_stripe? do
    {:ok, payment_intent} =
      StripeAPI.charge_off_session(
        cents,
        %{payment_method: "pm_card_#{card_brand}", metadata: metadata},
        "seed-#{Ecto.UUID.generate()}"
      )

    payment_intent
  else
    %{id: "pi_seed_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}", amount_received: cents, metadata: metadata}
  end
end

# Refunds a seeded Stripe payment in full and records it as the webhook would.
seed_refund = fn payment, fake_id ->
  cents = StripeAPI.to_stripe_amount(payment.amount)

  refund =
    if seed_stripe? do
      {:ok, refund} = StripeAPI.create_refund(payment.payment_intent_id, cents, "seed-#{Ecto.UUID.generate()}")
      refund
    else
      %{id: fake_id, payment_intent: payment.payment_intent_id, amount: cents, status: "succeeded"}
    end

  # The refund.created webhook can record it first.
  {:ok, outcome} = Edenflowers.Payments.record_stripe_refund(refund)
  true = outcome in [:recorded, :already_recorded]
end

Code.eval_file("seeds/production.exs", __DIR__)
Code.eval_file("seeds/cards.exs", __DIR__)

# Ash.Seed skips the actions, so draw from the same sequence they use.
next_reference = fn ->
  %{rows: [[reference]]} = Repo.query!("SELECT nextval('reference_seq')::text")
  reference
end

tax_rate = Ash.get!(TaxRate, %{name: "Standard 25.5%"}, authorize?: false)
reduced_tax_rate = Ash.get!(TaxRate, %{name: "Reduced 13.5%"}, authorize?: false)

category = fn slug -> Ash.get!(ProductCategory, %{slug: slug}, authorize?: false) end
bouquets_category = category.("bouquets")

# `details` maps a size to the details its category's product type shows.
create_product = fn attrs, prices, details ->
  product =
    Ash.Changeset.for_create(
      Product,
      :create,
      Map.merge(
        %{
          tax_rate_id: tax_rate.id,
          photo_slugs: ["https://placehold.co/1000x1250", "https://placehold.co/1000x1250?text=Side"],
          description:
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
          draft: false
        },
        attrs
      )
    )
    |> Ash.create!(authorize?: false)

  for {size, price} <- prices do
    Ash.Changeset.for_create(
      ProductVariant,
      :create,
      Map.merge(%{product_id: product.id, price: price, size: size, draft: false}, Map.get(details, size, %{}))
    )
    |> Ash.create!(authorize?: false)
  end

  product
end

bouquet_prices = [small: "40", medium: "50", large: "60"]

bouquet_details = %{
  small: %{height_cm: "30–40", stem_count: "10–12"},
  medium: %{height_cm: "40–50", stem_count: "15–20"},
  large: %{height_cm: "50–60", stem_count: "25–30"}
}

create_product.(
  %{product_category_id: bouquets_category.id, name: "Bouquet 1", featured: true, free_delivery: true},
  bouquet_prices,
  bouquet_details
)

# One size with only a height, as the florist sometimes leaves stems blank.
create_product.(
  %{product_category_id: bouquets_category.id, name: "Bouquet 2", featured: true},
  bouquet_prices,
  %{bouquet_details | large: %{height_cm: "50–60"}}
)

create_product.(%{product_category_id: bouquets_category.id, name: "Bouquet 3"}, bouquet_prices, bouquet_details)

create_product.(
  %{product_category_id: category.("plants").id, name: "Plant"},
  [small: "18", medium: "32", large: "55"],
  %{
    small: %{height_cm: "20–25", pot_cm: "12"},
    medium: %{height_cm: "40–50", pot_cm: "17"},
    large: %{height_cm: "80–90", pot_cm: "24"}
  }
)

# One of a kind, and the small one has sold, so the Overview flags it as sold out.
pre_loved =
  create_product.(
    %{product_category_id: category.("pre-loved").id, name: "Pre-Loved Item"},
    [small: "15", medium: "25"],
    %{}
  )

ProductVariant
|> Ash.Query.filter(product_id == ^pre_loved.id)
|> Ash.read!(authorize?: false)
|> Enum.each(&Ash.Seed.update!(&1, %{stock_quantity: if(&1.size == :small, do: 0, else: 1)}))

# Chocolate is an add-on: it shows in the store but can only be checked out
# alongside flowers.
chocolate_category =
  Ash.Changeset.for_create(ProductCategory, :create, %{
    name: "Chocolate",
    slug: "chocolate",
    visibility: :public,
    add_on: true,
    product_type: :chocolate,
    description: "Handmade chocolates to go with your flowers.",
    translations: %{
      "sv-FI": %{name: "Choklad", description: "Handgjord choklad till dina blommor."},
      fi: %{name: "Suklaa", description: "Käsintehtyä suklaata kukkiesi kanssa."}
    }
  })
  |> Ash.create!(authorize?: false)

# The truffles come in one size, so their page has no size to choose.
create_product.(
  %{
    product_category_id: chocolate_category.id,
    tax_rate_id: reduced_tax_rate.id,
    name: "Dark Chocolate Truffles",
    description: "A box of handmade chocolates, sold with a bouquet."
  },
  [{nil, "8"}],
  %{nil => %{weight_g: "120", pieces: "9"}}
)

# Left without products so the store's empty collection state can be seen.
Ash.Changeset.for_create(ProductCategory, :create, %{
  name: "Wreaths",
  slug: "wreaths",
  visibility: :public,
  product_type: :flowers,
  description: "Seasonal wreaths for doors and tables.",
  translations: %{
    "sv-FI": %{name: "Kransar", description: "Säsongens kransar för dörrar och bord."},
    fi: %{name: "Seppeleet", description: "Kauden seppeleitä oviin ja pöydille."}
  }
})
|> Ash.create!(authorize?: false)

create_product.(
  %{
    product_category_id: bouquets_category.id,
    name: "Florist's choice bouquet",
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
    featured: true,
    position: 0,
    free_delivery: true,
    subscribable: true
  },
  [small: "45", medium: "60", large: "75"],
  bouquet_details
)

# One promotion per state the admin list tells apart: running, ended, not
# started yet, and used up (its one use is the overdue order below).
for attrs <- [
      %{
        name: "Summer offer, 15% off",
        code: "SUMMER15",
        discount_rate: "0.15",
        minimum_cart_total: "30.00",
        start_date: nil,
        expiration_date: ~D[2099-07-01]
      },
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

# One per confidence level and payment state: unpaid, overdue and paid. The
# last is from a vendor without a VAT number.
for {document_id, vendor, vat, date, total, vat_amount, currency, category, description, confidence, paid_on, due_on} <-
      [
        {"doc-001", "Pohjanmaan Kukkutukku", "FI89012345", ~D[2026-04-03], "875.00", "178.65", :eur,
         :flowers_and_plants, "Bulk flower stock, spring delivery", :high, nil, Date.add(Date.utc_today(), 14)},
        {"doc-002", "Ravintola Faros", "FI34567890", ~D[2026-01-22], "68.40", "13.96", :eur, :entertainment,
         "Lunch with wedding client", :medium, nil, ~D[2026-02-05]},
        {"doc-003", "Kotipizza", nil, ~D[2026-03-19], "31.50", "6.43", :eur, :entertainment,
         "Lunch with venue coordinator", :low, ~D[2026-03-19], nil}
      ] do
  Expense
  |> Ash.Changeset.for_create(:ingest, %{
    document_id: document_id,
    vendor_name: vendor,
    vendor_vat_number: vat,
    date: date,
    paid_on: paid_on,
    due_on: due_on,
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
now = DateTime.now!("Europe/Helsinki")
today = DateTime.to_date(now)

[autumn_wreath, _table_arrangement, midsummer_crown] =
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
      name: "Christmas Table Arrangement",
      description:
        "A low arrangement for the Christmas table in a bowl of your choosing, with amaryllis, hyacinth, moss " <>
          "and evergreens. I'll show you how to keep it fresh through the holidays.",
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

jennie = Ash.get!(User, %{email: "info@edenflowers.fi"}, authorize?: false)

# Online course bookings. Ash.Seed for the same reason as orders below: checkout
# confirms a booking only once Stripe has taken the money, and like a placed
# order it keeps its PaymentIntent only on its Stripe payment. Elin cancelled
# and was refunded. The Christmas course is left empty on purpose, and the past
# one has its history.
[
  {autumn_wreath, "Anna Svensson", "anna.svensson@example.com", 3, :confirmed, "sv-FI"},
  {autumn_wreath, "Elin Sjöberg", "elin.sjoberg@example.com", 1, :cancelled, "sv-FI"},
  # No PaymentIntent: a fake one makes the ReconcilePayment cron fail against
  # Stripe, so it stays an abandoned checkout instead.
  {autumn_wreath, "Pekka Mäkinen", "pekka.makinen@example.com", 1, :pending, "fi"},
  {midsummer_crown, "Ida Westerlund", "ida.westerlund@example.com", 2, :confirmed, "sv-FI"}
]
|> Enum.each(fn {course, name, email, seats, status, locale} ->
  registration =
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
      confirmed_at: if(status != :pending, do: DateTime.utc_now()),
      confirmation_emailed_at: if(status != :pending, do: DateTime.utc_now()),
      cancelled_at: if(status == :cancelled, do: DateTime.utc_now())
    })

  if status != :pending do
    payment =
      Ash.Seed.seed!(Payment, %{
        course_registration_id: registration.id,
        amount: registration.amount,
        method: :stripe,
        payment_intent_id: seed_payment_intent.(registration.amount, "mastercard", %{}).id,
        paid_at: registration.confirmed_at,
        payment_method_type: "card",
        card_brand: "mastercard",
        card_last4: "4444"
      })

    # Cancelling refunds through Stripe, which refuses the made-up payments, so
    # the refund is recorded as the webhook would.
    if status == :cancelled, do: seed_refund.(payment, "re_seed_#{registration.reference}")
  end
end)

# One of Anna's group of three dropped out, and is still owed a refund.
CourseRegistration
|> Ash.Query.filter(email == "anna.svensson@example.com")
|> Ash.read_one!(authorize?: false)
|> Edenflowers.Courses.remove_registration_seat!(authorize?: false)

# Manual bookings, one per way Jennie is paid: at the course, already in cash,
# and by Payment Link.
for {name, email, seats, attrs} <- [
      {"Emma Nyström", "emma.nystrom@example.com", 1, %{payment_terms: :on_fulfillment}},
      {"Kristina Ahlroos", "kristina.ahlroos@example.com", 2,
       %{payment_terms: :on_fulfillment, amount: Decimal.mult(autumn_wreath.price, 2), payment_method: :cash}},
      {"Maria Nyberg", "maria.nyberg@example.com", 2, %{payment_terms: :payment_link}}
    ] do
  attrs
  |> Map.merge(%{
    course_id: autumn_wreath.id,
    name: name,
    email: email,
    seats: seats,
    locale: "sv-FI",
    email_customer?: false
  })
  |> Edenflowers.Courses.add_registration_manually!(actor: jennie)
end

# Placed orders. Checkout drives orders through a state machine and seals them
# once placed, so normal Ash actions can't construct a finished order. Ash.Seed
# writes attributes directly, bypassing transitions and policies: the right
# escape hatch for fixtures.
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

variants =
  ProductVariant
  |> Ash.Query.load([:photo_slug, product: [:tax_rate]])
  |> Ash.read!(authorize?: false)

variant_for = fn product_name, size ->
  Enum.find(variants, fn v -> v.product.name == product_name and v.size == size end)
end

# Line items snapshot the variant the same way PopulateFromVariant does at
# checkout, so the Overview's subtotal/tax aggregates add up.
line_item = fn product_name, size, quantity ->
  variant = variant_for.(product_name, size)

  %{
    product_id: variant.product.id,
    product_variant_id: variant.id,
    quantity: quantity,
    unit_price: variant.price,
    tax_rate: variant.product.tax_rate.percentage,
    product_name: variant.product.name,
    product_image_slug: variant.photo_slug,
    variant_size: variant.size,
    free_delivery: variant.product.free_delivery,
    is_card: false
  }
end

# Checkout enforces one card per order (SwapCardLineItem).
card_line_item = fn -> %{line_item.("Dahlias", :medium, 1) | is_card: true} end

# Inside the free delivery radius.
nearby_address = %{
  delivery_address: "Gerbyntie 16, 65230 Vaasa",
  geocoded_address: "Gerbyvägen 16, 65230 Vasa",
  position: "63.1157,21.61864",
  here_id: "here:af:streetsection:olhtF0fcY2Tg2P7kFPBnMB:EAIaAjE2",
  distance: 1651
}

# Far enough out to pay for delivery.
distant_address = %{
  delivery_address: "Sundomintie 130, 65410 Sundom",
  geocoded_address: "Sundomvägen 130, 65410 Vasa",
  position: "63.03232,21.54662",
  here_id: "here:af:streetsection:DnEELU-r45CN9NK9d3YMnB:EAIaAzEzMA",
  distance: 12_711
}

# Takes the order's attributes plus :fulfillment_option, :items (line item maps),
# an optional :promotion, and :payment_card ({brand, last4}, or nil if unpaid).
seed_placed_order = fn attrs ->
  {option, attrs} = Map.pop!(attrs, :fulfillment_option)
  {items, attrs} = Map.pop!(attrs, :items)
  {promotion, attrs} = Map.pop(attrs, :promotion)
  {payment_card, attrs} = Map.pop(attrs, :payment_card)
  {fulfillment_status, attrs} = Map.pop(attrs, :fulfillment_status)
  fulfillment_status = fulfillment_status || :pending
  %{error: nil} = fee = Fee.calculate(option, attrs[:distance] || 0)

  order =
    Ash.Seed.seed!(
      Order,
      Map.merge(
        %{
          order_reference: next_reference.(),
          state: :placed,
          fulfillment_status: fulfillment_status,
          # Already emailed, so the admin menu offers to resend rather than send.
          receipt_emailed_at: DateTime.utc_now(),
          fulfillment_emailed_at: if(fulfillment_status == :fulfilled, do: DateTime.utc_now()),
          ordered_at: DateTime.utc_now(),
          locale: "sv-FI",
          fulfillment_option_id: option.id,
          fulfillment_option_name: option.name,
          fulfillment_method: option.fulfillment_method,
          quoted_fulfillment_fee: fee.fulfillment_fee,
          in_free_delivery_zone: fee.in_free_delivery_zone,
          fulfillment_tax_rate: tax_rate.percentage,
          # Snapshot the promotion the same way SnapshotPromotion does at checkout.
          # LineItem.discount keys off order.discount_rate + promotion_id, so both
          # the relationship and the frozen columns must be set for totals to match.
          promotion_id: promotion && promotion.id,
          discount_rate: promotion && promotion.discount_rate,
          promotion_name: promotion && promotion.name,
          promotion_code: promotion && to_string(promotion.code)
        },
        attrs
      )
    )

  for item <- items do
    Ash.Seed.seed!(LineItem, Map.put(item, :order_id, order.id))
  end

  # Snapshot the VAT breakdown the same way SnapshotVatBreakdown does at checkout.
  # Clearing state makes Vat.breakdown compute from the line items rather than
  # read the snapshot this is about to write.
  order = Ash.load!(order, [:grand_total | Vat.load(nil, nil, nil)], authorize?: false)
  Ash.Seed.update!(order, %{vat_breakdown: Vat.breakdown(%{order | state: nil})})

  if payment_card do
    {card_brand, card_last4} = payment_card

    Ash.Seed.seed!(Payment, %{
      order_id: order.id,
      amount: order.grand_total,
      method: :stripe,
      payment_intent_id: seed_payment_intent.(order.grand_total, card_brand, %{}).id,
      paid_at: order.ordered_at,
      payment_method_type: "card",
      card_brand: card_brand,
      card_last4: card_last4
    })
  end

  order
end

# Fulfillment dates are relative to whenever the seed runs. Future dates are
# resolved through the same availability rules as checkout, so running seeds on
# a Monday or after a same-day deadline cannot create an impossible order.
shop_calendar = Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)

fulfillment_date_for = fn days_out ->
  requested_date = Date.add(today, days_out)

  if days_out < 0 do
    Stream.iterate(requested_date, &Date.add(&1, -1))
    |> Enum.find(fn date ->
      date not in shop_calendar.disabled_dates and
        (date in shop_calendar.enabled_dates or Weekday.from_date(date) in shop_calendar.available_days)
    end)
  else
    Stream.iterate(requested_date, &Date.add(&1, 1))
    |> Enum.find(fn date -> Availability.unavailable_reason(shop_calendar, date, now) == nil end)
  end
end

orders = [
  # A gift with a card, delivered today, outside the free delivery radius.
  Map.merge(distant_address, %{
    customer_name: "Mikael Lindholm",
    customer_email: "mikael.lindholm@example.fi",
    fulfillment_option: home_delivery,
    fulfillment_date: today,
    gift: true,
    recipient_name: "Sofia Lindholm",
    recipient_phone_number: "050 9876543",
    card_message: "Happy birthday, with love.",
    items: [line_item.("Bouquet 3", :large, 1), card_line_item.()]
  }),
  # Cart total well above the promo's €30 minimum so the discount applies.
  Map.merge(nearby_address, %{
    customer_name: "Liisa Mäkinen",
    customer_email: "liisa.makinen@example.fi",
    fulfillment_option: home_delivery,
    fulfillment_date: fulfillment_date_for.(4),
    recipient_name: "Liisa Mäkinen",
    customer_phone_number: "041 5550099",
    locale: "fi",
    promotion: promotion_by_code.("SUMMER15"),
    items: [line_item.("Bouquet 2", :large, 2), line_item.("Plant", :medium, 1)]
  }),
  # Ordered a few days back and already delivered, so it lands in the Overview's
  # completed side. Both dates sit in the past, in order.
  Map.merge(nearby_address, %{
    customer_name: "Hanna Järvinen",
    customer_email: "hanna.jarvinen@example.fi",
    fulfillment_option: home_delivery,
    ordered_at: DateTime.add(DateTime.utc_now(), -6, :day),
    fulfillment_date: fulfillment_date_for.(-2),
    recipient_name: "Hanna Järvinen",
    customer_phone_number: "045 3217654",
    fulfillment_status: :fulfilled,
    items: [line_item.("Bouquet 2", :medium, 1)]
  }),
  # Paid, but its pickup day has passed without Jennie marking it collected.
  %{
    customer_name: "Tuula Rantanen",
    customer_email: "tuula.rantanen@example.fi",
    fulfillment_option: store_pickup,
    ordered_at: DateTime.add(DateTime.utc_now(), -4, :day),
    fulfillment_date: fulfillment_date_for.(-1),
    locale: "fi",
    promotion: promotion_by_code.("MOR10"),
    items: [line_item.("Bouquet 3", :medium, 1)]
  },
  # A large mixed cart with both VAT rates. The four below are changed after
  # placing, further down.
  %{
    customer_name: "Erik Sundström",
    customer_email: "erik.sundstrom@example.fi",
    fulfillment_option: store_pickup,
    fulfillment_date: fulfillment_date_for.(5),
    items: [
      line_item.("Bouquet 1", :large, 1),
      line_item.("Bouquet 2", :small, 2),
      line_item.("Plant", :large, 1),
      line_item.("Dark Chocolate Truffles", nil, 1)
    ]
  },
  %{
    customer_name: "Petra Holm",
    customer_email: "petra.holm@example.fi",
    fulfillment_option: store_pickup,
    fulfillment_date: fulfillment_date_for.(2),
    items: [line_item.("Bouquet 3", :small, 1)]
  },
  %{
    customer_name: "Oskar Wikström",
    customer_email: "oskar.wikstrom@example.fi",
    fulfillment_option: store_pickup,
    fulfillment_date: fulfillment_date_for.(3),
    locale: "en-GB",
    items: [line_item.("Plant", :large, 1)]
  },
  %{
    customer_name: "Nora Back",
    customer_email: "nora.back@example.fi",
    fulfillment_option: store_pickup,
    fulfillment_date: fulfillment_date_for.(4),
    items: [line_item.("Bouquet 1", :small, 1), line_item.("Plant", :medium, 1)]
  },
  # With Mikael's, today's Overview has a timed delivery ahead of an untimed one,
  # and a pickup.
  Map.merge(nearby_address, %{
    customer_name: "Karin Öst",
    customer_email: "karin.ost@example.fi",
    fulfillment_option: home_delivery,
    fulfillment_date: today,
    fulfillment_time_start: ~T[10:00:00],
    fulfillment_time_end: ~T[12:00:00],
    recipient_name: "Karin Öst",
    customer_phone_number: "040 1112233",
    items: [line_item.("Bouquet 2", :medium, 1)]
  }),
  %{
    customer_name: "Ida Nyberg",
    customer_email: "ida.nyberg@example.fi",
    fulfillment_option: store_pickup,
    fulfillment_date: today,
    fulfillment_time_start: ~T[15:00:00],
    items: [line_item.("Bouquet 1", :medium, 2)]
  },
  # Tomorrow itself, not the next open day, so the Overview's Tomorrow always has a delivery.
  Map.merge(distant_address, %{
    customer_name: "Anders Björk",
    customer_email: "anders.bjork@example.fi",
    fulfillment_option: home_delivery,
    fulfillment_date: Date.add(today, 1),
    gift: true,
    recipient_name: "Maja Björk",
    items: [line_item.("Bouquet 3", :small, 1)]
  })
]

for {attrs, index} <- Enum.with_index(orders) do
  user = Accounts.upsert_user!(attrs.customer_email, attrs.customer_name, actor: Actors.system_actor())

  seed_placed_order.(
    Map.merge(attrs, %{
      user_id: user.id,
      gift: Map.get(attrs, :gift, false),
      payment_card: Enum.at([{"visa", "4242"}, {"mastercard", "4444"}, {"amex", "0005"}], rem(index, 3))
    })
  )
end

# Subscriptions, one per state the admin list and account page show, each with
# the order that started it and some with later deliveries (Occurrences).
# Ash.Seed for the same reason as the orders above. As in the app, the schedule
# runs on whole intervals from the first order's date: each Occurrence is the
# next date on it, and next_fulfillment_date the one after the latest. Active
# next dates sit beyond the lead time and the change cutoff, so the hourly
# occurrence job doesn't charge them as soon as they're seeded, and customers
# can still change them.
alias Edenflowers.Orders.Subscription

weekly_bouquet = fn size -> variant_for.("Florist's choice bouquet", size) end

seed_subscription_order = fn subscription, user, attrs ->
  paid? = Map.get(attrs, :paid?, true)
  online? = attrs.origin == :online

  item =
    line_item.("Florist's choice bouquet", attrs.size, 1)
    # Only the order that started the subscription carries the interval; an
    # Occurrence's line is a one-off.
    |> Map.put(:interval_weeks, if(online?, do: subscription.interval_weeks))

  nearby_address
  |> Map.merge(%{
    fulfillment_option: home_delivery,
    items: [item],
    payment_card: if(paid?, do: {subscription.card_brand, subscription.card_last4}),
    origin: attrs.origin,
    subscription_id: subscription.id,
    subscription_date: attrs[:subscription_date],
    fulfillment_status: attrs[:fulfillment_status],
    order_details_emailed_at: if(not paid?, do: DateTime.utc_now()),
    customer_name: user.name,
    customer_email: to_string(user.email),
    user_id: user.id,
    gift: subscription.recipient_name != user.name,
    card_message: attrs[:card_message],
    customer_phone_number: subscription.customer_phone_number,
    recipient_name: subscription.recipient_name,
    recipient_phone_number: subscription.recipient_phone_number,
    fulfillment_date: attrs.fulfillment_date,
    payment_link_token: if(not paid?, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)),
    stripe_customer_id: if(online?, do: subscription.stripe_customer_id),
    stripe_payment_method_id: if(online?, do: subscription.stripe_payment_method_id),
    locale: subscription.locale
  })
  |> seed_placed_order.()
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
  # A gift, paused before its second delivery was charged, so its next date
  # stays put until it resumes.
  %{
    email: "otto.makinen@example.fi",
    name: "Otto Mäkinen",
    state: :paused,
    size: :small,
    interval_weeks: 4,
    first_days_out: -28,
    recipient_name: "Ingrid Mäkinen",
    card_message: "Lots of love from Otto",
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
    size: :large,
    interval_weeks: 2,
    first_days_out: -21,
    recipient_name: "Jonas Berg",
    locale: "sv-FI",
    occurrences: [%{fulfillment_status: :fulfilled}]
  }
]

for attrs <- subscriptions do
  user = Accounts.upsert_user!(attrs.email, attrs.name, actor: Actors.system_actor())
  first_date = fulfillment_date_for.(attrs.first_days_out)
  scheduled_date = fn n -> Date.add(first_date, n * attrs.interval_weeks * 7) end

  {customer_id, payment_method_id} =
    if seed_stripe? do
      {:ok, customer} = StripeAPI.create_customer(%{email: attrs.email, name: attrs.name})
      {:ok, payment_method} = StripeAPI.attach_payment_method("pm_card_visa", customer.id)
      {customer.id, payment_method.id}
    else
      {"cus_seed_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}",
       "pm_seed_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"}
    end

  subscription =
    Ash.Seed.seed!(Subscription, %{
      user_id: user.id,
      product_variant_id: weekly_bouquet.(attrs.size).id,
      fulfillment_option_id: home_delivery.id,
      state: attrs.state,
      interval_weeks: attrs.interval_weeks,
      next_fulfillment_date: scheduled_date.(length(attrs.occurrences) + 1),
      customer_phone_number: "045 7651234",
      recipient_name: attrs.recipient_name,
      recipient_phone_number: if(attrs.recipient_name != attrs.name, do: "040 1234567"),
      delivery_address: nearby_address.delivery_address,
      card_message: attrs[:card_message],
      locale: attrs.locale,
      stripe_customer_id: customer_id,
      stripe_payment_method_id: payment_method_id,
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
# address is geocoded, and only the seeded Stripe payments and refunds call
# Stripe. Every customer email is marked as already sent, for the same reason
# as above.
alias Edenflowers.Orders
alias Edenflowers.Payments

custom_line = fn description, unit_price ->
  %{
    "kind" => "custom",
    "product_name" => description,
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
      fulfillment_date: fulfillment_date_for.(attrs[:days_out] || 2),
      email_customer?: false
    },
    Map.delete(attrs, :days_out)
  )
  |> Orders.place_custom_order!(actor: jennie)
end

# Phoned in for a funeral: no email, so Jennie copies the payment link into a text message.
place_custom.(%{
  customer_name: "Margareta Holm",
  customer_phone_number: "040 7654321",
  recipient_name: "Funeral of Gunnar Holm",
  card_message: "Tack för allt, vila i frid.",
  florist_note: "White roses and lilies only. The funeral home collects at 10:00, service at 11:00.",
  line_items: [
    custom_line.("Funeral spray, white roses and lilies", "120.00"),
    catalogue_line.("Condolence", :medium, 1)
  ]
})

# Collected three weeks ago by a phone-only customer who promised to pay, so the
# Overview flags the payment as overdue. Placed today and then backdated, as
# Jennie can't place an order in the past.
fulfilled_unpaid =
  place_custom.(%{
    customer_name: "Bertil Ek",
    customer_phone_number: "044 2223344",
    days_out: 0,
    line_items: [catalogue_line.("Bouquet 1", :small, 1)]
  })
  |> Orders.mark_order_fulfilled!(actor: jennie)

Ash.Seed.update!(fulfilled_unpaid, %{
  ordered_at: DateTime.add(DateTime.utc_now(), -24, :day),
  fulfillment_date: fulfillment_date_for.(-21)
})

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

online_order = fn customer_name ->
  Order
  |> Ash.Query.filter(customer_name == ^customer_name)
  |> Ash.Query.load([:line_items, :payments])
  |> Ash.read_one!(authorize?: false)
end

# An online order the customer asked to add to by email after paying: it now
# has a balance to collect and a payment link for just that.
erik = online_order.("Erik Sundström")

kept_lines = Enum.map(erik.line_items, &%{"id" => &1.id, "quantity" => to_string(&1.quantity)})

Orders.edit_order!(erik, %{line_items: kept_lines ++ [catalogue_line.("Plant", :small, 1)]}, actor: jennie)
Orders.open_payment_link!(erik, actor: jennie)

# A custom order paid in part by link, the rest still owed. The link payment
# is recorded as the Stripe webhook would, which may get there first.
part_paid =
  place_custom.(%{
    customer_name: "Johanna Lind",
    customer_email: "johanna.lind@example.fi",
    locale: "en-GB",
    days_out: 6,
    line_items: [catalogue_line.("Bouquet 3", :medium, 1)]
  })

part_paid = Orders.get_order_for_admin!(part_paid.id, actor: jennie)
link_payment = seed_payment_intent.(part_paid.balance, "visa", %{"order_id" => part_paid.id})
Ash.Seed.update!(part_paid, %{payment_intent_id: link_payment.id})

{:ok, outcome} = Payments.complete(link_payment)
true = outcome in [:completed, :already_completed]

# complete/1 looks the method up in Stripe, which a made-up PaymentIntent
# isn't in, so the payment is named here instead.
unless seed_stripe? do
  Payment
  |> Ash.Query.filter(payment_intent_id == ^link_payment.id)
  |> Ash.read_one!(authorize?: false)
  |> Ash.Seed.update!(%{payment_method_type: "mobilepay"})
end

part_paid = Orders.get_order_for_admin!(part_paid.id, actor: jennie, load: [:line_items])
Ash.Seed.update!(part_paid, %{receipt_emailed_at: DateTime.utc_now()})
[bouquet] = part_paid.line_items

Orders.edit_order!(
  part_paid,
  %{
    line_items: [
      %{"id" => bouquet.id, "quantity" => "1"},
      custom_line.("Vase, hand-thrown", "35.00")
    ]
  },
  actor: jennie
)

# Called off and refunded in full. Ash.Seed because cancelling refunds through
# Stripe, which refuses the made-up payments; seed_refund records it instead.
petra = online_order.("Petra Holm")
Ash.Seed.update!(petra, %{fulfillment_status: :cancelled, cancelled_at: DateTime.utc_now()})
[petra_payment] = petra.payments

seed_refund.(petra_payment, "re_seed_#{petra.order_reference}")

# Called off the day before, so Jennie kept the payment.
oskar = Ash.load!(online_order.("Oskar Wikström"), :amount_held, authorize?: false)
Orders.cancel_order!(oskar, %{refund: 0, held: oskar.amount_held}, actor: jennie)

# Paid, then the plant was out of stock: money to hand back through Stripe.
nora = online_order.("Nora Back")
[bouquet | _] = Enum.filter(nora.line_items, &(&1.product_name == "Bouquet 1"))

Orders.edit_order!(nora, %{line_items: [%{"id" => bouquet.id, "quantity" => "1"}]}, actor: jennie)

# Paid in cash, then the gift wrap was left off: money to hand back in person.
cash =
  place_custom.(%{
    customer_name: "Greta Lund",
    customer_phone_number: "040 5557788",
    days_out: 2,
    payment_terms: :on_fulfillment,
    line_items: [catalogue_line.("Bouquet 2", :medium, 1), custom_line.("Gift wrapping", "5.00")]
  })

cash = Orders.get_order_for_admin!(cash.id, actor: jennie, load: [:line_items])
[bouquet | _] = Enum.filter(cash.line_items, &(&1.product_variant_id != nil))
cash = Orders.record_payment!(cash, cash.balance, :cash, actor: jennie)

Orders.edit_order!(cash, %{line_items: [%{"id" => bouquet.id, "quantity" => "1"}]}, actor: jennie)

# A free replacement for a returning customer whose first bouquet wilted.
place_custom.(%{
  customer_name: "Liisa Mäkinen",
  customer_email: "liisa.makinen@example.fi",
  locale: "fi",
  days_out: 1,
  payment_terms: :on_fulfillment,
  florist_note: "Replaces her earlier delivery, which wilted the next day.",
  line_items: [custom_line.("Replacement bouquet", "0.00")]
})

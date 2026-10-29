# The rows the admin can't create: admins, tax rates, fulfillment options and
# product categories. Run once against an empty production database, see the
# "New server" section of infra/README.md.
# priv/repo/seeds.exs runs this first and builds its dev fixtures on top.

alias Edenflowers.Accounts.User
alias Edenflowers.Catalog.ProductCategory
alias Edenflowers.Fulfillment.FulfillmentOption
alias Edenflowers.Pricing.TaxRate
alias Edenflowers.Repo

Repo.transaction(fn ->
  # `admin` is writable?: false on the resource so normal Ash actions can't set
  # it — raw SQL is the appropriate escape hatch for seed setup.
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

  # Flowers, plants, cards, pre-loved items (no margin scheme), delivery and
  # courses are standard rate; chocolates are food, so reduced.
  standard_tax_rate =
    TaxRate
    |> Ash.Changeset.for_create(:create, %{name: "Standard 25.5%", percentage: "0.255"})
    |> Ash.create!(authorize?: false)

  TaxRate
  |> Ash.Changeset.for_create(:create, %{name: "Reduced 13.5%", percentage: "0.135"})
  |> Ash.create!(authorize?: false)

  # Prices, distances and days are starting values; the florist edits them in the admin.
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
    tax_rate_id: standard_tax_rate.id,
    translations: %{
      "sv-FI": %{name: "Hemleverans"},
      fi: %{name: "Kotiinkuljetus"}
    }
  })
  |> Ash.create!(authorize?: false)

  FulfillmentOption
  |> Ash.Changeset.for_create(:create, %{
    name: "In store pickup",
    sort_key: 1,
    fulfillment_method: :pickup,
    rate_type: :fixed,
    base_price: "0.00",
    tax_rate_id: standard_tax_rate.id,
    translations: %{
      "sv-FI": %{name: "Avhämtning i butiken"},
      fi: %{name: "Nouto myymälästä"}
    }
  })
  |> Ash.create!(authorize?: false)

  Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)
  |> Ash.Seed.update!(%{available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]})

  categories = [
    %{
      name: "Bouquets",
      slug: "bouquets",
      position: 0,
      visibility: :public,
      description: "The flowers change with the seasons, but the style stays mine.",
      translations: %{
        "sv-FI": %{
          name: "Buketter",
          description: "Blommorna skiftar med årstiderna, men stilen är min egen."
        },
        fi: %{
          name: "Kukkakimput",
          description: "Kukat vaihtuvat vuodenaikojen mukaan, mutta tyyli pysyy omanani."
        }
      }
    },
    %{
      name: "Plants",
      slug: "plants",
      position: 1,
      visibility: :public,
      product_type: :plant,
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
    },
    # Cards are surfaced only at checkout via ProductVariant.for_card_drawer.
    # visibility: :hidden keeps the category out of the store ribbon while still
    # allowing its products to be read by that action.
    %{
      name: "Cards",
      slug: "cards",
      visibility: :hidden,
      add_on: true,
      product_type: :card,
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
    },
    %{
      name: "Pre-Loved",
      slug: "pre-loved",
      position: 2,
      visibility: :public,
      product_type: :other,
      description: "Second-hand finds looking for a new home.",
      translations: %{
        "sv-FI": %{
          name: "Begagnat",
          description: "Begagnade fynd som söker ett nytt hem."
        },
        fi: %{
          name: "Käytetty",
          description: "Käytettyjä löytöjä, jotka etsivät uutta kotia."
        }
      }
    }
  ]

  for attrs <- categories do
    ProductCategory
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(authorize?: false)
  end
end)

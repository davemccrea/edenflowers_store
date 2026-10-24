# The greeting cards from the old site, with their photos in images/cards/.
# Safe to rerun: a card is matched by its English name and updated in place.
#
# Dev:  priv/repo/seeds.exs runs it, or mix run priv/repo/seeds/cards.exs alone
# Prod: `just sync-images` and `just backup` first, then
#   ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'Code.eval_file(Application.app_dir(:edenflowers, \"priv/repo/seeds/cards.exs\"))'"

alias Edenflowers.Catalog.Product
alias Edenflowers.Catalog.ProductCategory
alias Edenflowers.Pricing.TaxRate

require Ash.Query

descriptions = %{
  small: %{
    en: "A small card with room for a short message.",
    sv: "Ett litet kort med plats för en kort hälsning.",
    fi: "Pieni kortti lyhyelle viestille."
  },
  medium: %{
    en: "A medium card with room for a few lines.",
    sv: "Ett mellanstort kort med plats för några rader.",
    fi: "Keskikokoinen kortti muutamalle riville."
  },
  large: %{
    en: "A large card with room for a longer message.",
    sv: "Ett stort kort med plats för en längre hälsning.",
    fi: "Iso kortti pidemmälle viestille."
  }
}

# {name, size, price, photo}
cards = [
  {"Red oak leaves", :small, "1.90", "red_oak_leaves.png"},
  {"Flower heart", :small, "1.90", "flower_heart.png"},
  {"Botanical beetle", :small, "1.90", "botanical_beetle.png"},
  {"Sunflowers with bumble bee", :small, "1.90", "sunflowers_with_bumble_bee.png"},
  {"Giraffes in love", :small, "1.90", "giraffes_in_love.png"},
  {"Dahlias", :medium, "3.50", "dahlias.png"},
  {"June flowers", :medium, "3.50", "june_flowers.png"},
  {"Poppies", :medium, "3.50", "poppies.png"},
  {"Pansy flower", :medium, "3.50", "pansy_flower.png"},
  {"Cherries", :medium, "3.50", "cherries.png"},
  {"Magnolia", :medium, "3.50", "magnolia.png"},
  {"Condolence", :medium, "3.50", "kondoleans.png"},
  {"Meadow", :large, "4.90", "meadow.png"},
  {"Malva", :large, "4.90", "malva.png"},
  {"Kira", :large, "4.90", "kira.png"},
  {"Love spell", :large, "4.90", "love_spell.png"},
  {"Aruba", :large, "4.90", "aruba.png"},
  {"Monroe", :large, "4.90", "monroe.png"},
  {"Botanica", :large, "4.90", "botanica.png"},
  {"Cherry blossom", :large, "4.90", "cherry_blossom.png"}
]

# The other designs go by their English names in every language.
translated_names = %{"Condolence" => %{sv: "Kondoleans", fi: "Surunvalittelu"}}

category = ProductCategory |> Ash.Query.filter(slug == "cards") |> Ash.read_one!(authorize?: false)
tax_rate = TaxRate |> Ash.Query.filter(name == "Standard 25.5%") |> Ash.read_one!(authorize?: false)

Edenflowers.Repo.transaction(fn ->
  for {name, size, price, photo} <- cards do
    description = descriptions[size]
    names = Map.get(translated_names, name, %{sv: name, fi: name})

    attrs = %{
      name: name,
      description: description.en,
      photo_slugs: ["local:///cards/" <> photo],
      product_category_id: category.id,
      tax_rate_id: tax_rate.id,
      draft: false,
      translations: %{
        "sv-FI": %{name: names.sv, description: description.sv},
        fi: %{name: names.fi, description: description.fi}
      }
    }

    variant = %{size: size, price: price, draft: false}

    existing =
      Product
      |> Ash.Query.filter(name == ^name)
      |> Ash.Query.load(:product_variants)
      |> Ash.read_one!(authorize?: false)

    case existing do
      nil ->
        Product
        |> Ash.Changeset.for_create(:create, Map.put(attrs, :product_variants, [variant]))
        |> Ash.create!(authorize?: false)

      product ->
        # Keeps the size's id, so past order lines still point at it.
        variants =
          case product.product_variants do
            [current | _] -> [Map.put(variant, :id, current.id)]
            [] -> [variant]
          end

        product
        |> Ash.Changeset.for_update(:update, Map.put(attrs, :product_variants, variants))
        |> Ash.update!(authorize?: false)
    end

    IO.puts("#{name}: #{size}, #{price} €")
  end
end)

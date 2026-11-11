defmodule Edenflowers.Catalog.ProductTest do
  use Edenflowers.DataCase, async: true
  import Generator

  alias Edenflowers.Catalog

  setup do
    tax_rate = generate(tax_rate())
    product_category = generate(product_category())
    {:ok, tax_rate: tax_rate, product_category: product_category}
  end

  describe "Catalog.list_featured_cards" do
    test "lists only Favourite cards in stock, of any size", %{tax_rate: tax_rate} do
      cards = generate(product_category(slug: "cards", visibility: :hidden))

      card = fn featured, size, stock_quantity ->
        product =
          generate(product(tax_rate_id: tax_rate.id, product_category_id: cards.id, draft: false, featured: featured))

        generate(product_variant(product_id: product.id, draft: false, size: size, stock_quantity: stock_quantity))
        product
      end

      large = card.(true, :large, nil)
      small = card.(true, :small, nil)
      not_favourite = card.(false, :large, nil)
      sold_out = card.(true, :large, 0)

      ids = Enum.map(Catalog.list_featured_cards!(authorize?: false), & &1.id)

      assert large.id in ids
      assert small.id in ids
      refute not_favourite.id in ids
      refute sold_out.id in ids
    end

    test "lists no more cards than the fan holds", %{tax_rate: tax_rate} do
      cards = generate(product_category(slug: "cards", visibility: :hidden))

      for _ <- 0..Catalog.Product.max_fan_cards() do
        card = generate(product(tax_rate_id: tax_rate.id, product_category_id: cards.id, draft: false, featured: true))
        generate(product_variant(product_id: card.id, draft: false))
      end

      assert length(Catalog.list_featured_cards!(authorize?: false)) == Catalog.Product.max_fan_cards()
    end

    test "keeps Favourite cards out of the home page's Favourites", %{tax_rate: tax_rate} do
      cards = generate(product_category(slug: "cards", visibility: :hidden))
      card = generate(product(tax_rate_id: tax_rate.id, product_category_id: cards.id, draft: false, featured: true))
      generate(product_variant(product_id: card.id, draft: false, size: :large))

      refute card.id in Enum.map(Catalog.list_featured_products!(authorize?: false), & &1.id)
    end
  end

  describe "Catalog.list_store_products filtering" do
    test "excludes products whose only size was removed", %{tax_rate: tax_rate} do
      published_category = generate(product_category(visibility: :public))
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))
      variant = generate(product_variant(product_id: product.id))

      Ash.destroy!(variant, authorize?: false)

      products = Catalog.list_store_products!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == product.id end)
    end

    test "excludes draft products", %{tax_rate: tax_rate} do
      published_category = generate(product_category(visibility: :public))

      draft_product =
        generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: true))

      _variant = generate(product_variant(product_id: draft_product.id))

      products = Catalog.list_store_products!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == draft_product.id end)
    end

    test "excludes products without product_variants", %{tax_rate: tax_rate} do
      published_category = generate(product_category(visibility: :public))

      product_no_variants =
        generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))

      products = Catalog.list_store_products!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == product_no_variants.id end)
    end

    test "excludes products with draft category", %{tax_rate: tax_rate} do
      draft_category = generate(product_category(visibility: :draft))
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: draft_category.id, draft: false))
      _variant = generate(product_variant(product_id: product.id))

      products = Catalog.list_store_products!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == product.id end)
    end

    test "carries each product's cheapest price", %{tax_rate: tax_rate} do
      published_category = generate(product_category(visibility: :public))
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))
      generate(product_variant(product_id: product.id, price: "24.00"))
      generate(product_variant(product_id: product.id, price: "15.99"))

      products = Catalog.list_store_products!(authorize?: false)
      found_product = Enum.find(products, fn p -> p.id == product.id end)

      assert Decimal.equal?(found_product.cheapest_price, "15.99")
    end
  end

  describe "Catalog.list_products_by_category filtering" do
    test "returns only products in specified category", %{tax_rate: tax_rate} do
      category_a = generate(product_category(visibility: :public))
      category_b = generate(product_category(visibility: :public))

      product_a = generate(product(tax_rate_id: tax_rate.id, product_category_id: category_a.id, draft: false))
      _variant_a = generate(product_variant(product_id: product_a.id))

      product_b = generate(product(tax_rate_id: tax_rate.id, product_category_id: category_b.id, draft: false))
      _variant_b = generate(product_variant(product_id: product_b.id))

      products = Catalog.list_products_by_category!(category_a.id, authorize?: false)

      assert Enum.any?(products, fn p -> p.id == product_a.id end)
      refute Enum.any?(products, fn p -> p.id == product_b.id end)
    end

    test "returns empty list when category has no qualifying products", %{tax_rate: _tax_rate} do
      empty_category = generate(product_category(visibility: :public))

      products = Catalog.list_products_by_category!(empty_category.id, authorize?: false)

      assert products == []
    end

    test "lists products by position, then name", %{tax_rate: tax_rate} do
      category = generate(product_category(visibility: :public))

      for {name, position} <- [{"A", nil}, {"B", 1}, {"C", 0}] do
        product =
          generate(
            product(
              name: name,
              position: position,
              tax_rate_id: tax_rate.id,
              product_category_id: category.id,
              draft: false
            )
          )

        generate(product_variant(product_id: product.id))
      end

      products = Catalog.list_products_by_category!(category.id, authorize?: false)

      assert Enum.map(products, & &1.name) == ["C", "B", "A"]
    end
  end

  describe "a product's photos" do
    test "must number 1 to 8" do
      for photo_slugs <- [[], Enum.map(1..9, &"#{&1}.jpg")] do
        assert {:error, %Ash.Error.Invalid{errors: [%{field: :photo_slugs}]}} =
                 update(generate(product()), %{photo_slugs: photo_slugs})
      end
    end

    test "the first is the main photo, which a size without its own follows" do
      product = generate(product(photo_slugs: ["a.jpg", "b.jpg"]))
      generate(product_variant(product_id: product.id))

      product = update!(product, %{photo_slugs: ["b.jpg", "a.jpg"]})

      assert [%{photo_slug: "b.jpg"}] =
               Ash.load!(product, [:main_photo_slug, product_variants: [:photo_slug]]).product_variants

      assert Ash.load!(product, :main_photo_slug).main_photo_slug == "b.jpg"
    end

    test "a size can only pick one of its product's photos" do
      product = generate(product(photo_slugs: ["a.jpg", "b.jpg"]))
      variant = generate(product_variant(product_id: product.id))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :own_photo_slug, path: [:product_variants, 0]}]}} =
               update(product, %{product_variants: [%{id: variant.id, own_photo_slug: "c.jpg"}]})

      product = update!(product, %{product_variants: [%{id: variant.id, own_photo_slug: "b.jpg"}]})

      assert [%{own_photo_slug: "b.jpg"}] = Ash.load!(product, :product_variants).product_variants
    end

    test "removing the photo a size uses sends it back to the main photo" do
      product = generate(product(photo_slugs: ["a.jpg", "b.jpg"]))
      keeps = generate(product_variant(product_id: product.id, own_photo_slug: "a.jpg"))
      loses = generate(product_variant(product_id: product.id, own_photo_slug: "b.jpg"))

      update!(product, %{photo_slugs: ["a.jpg"]})

      assert Ash.get!(Catalog.ProductVariant, keeps.id, authorize?: false).own_photo_slug == "a.jpg"
      assert Ash.get!(Catalog.ProductVariant, loses.id, authorize?: false, load: [:photo_slug]).photo_slug == "a.jpg"
    end

    test "the main photo pictures Medium, and a size's own photo pictures that size" do
      product = generate(product(photo_slugs: ["main.jpg", "large.jpg", "shared.jpg", "detail.jpg"]))
      generate(product_variant(product_id: product.id, size: :medium, own_photo_slug: nil))
      generate(product_variant(product_id: product.id, size: :large, own_photo_slug: "large.jpg"))
      generate(product_variant(product_id: product.id, size: :small, own_photo_slug: "shared.jpg"))
      generate(product_variant(product_id: product.id, size: :large, own_photo_slug: "shared.jpg"))

      # Only photos associated with exactly one size belong in pictured_sizes.
      # A shared photo or a photo unused by any size cannot identify a specific size.
      assert Ash.load!(product, :pictured_sizes).pictured_sizes == %{"main.jpg" => :medium, "large.jpg" => :large}
    end

    test "without a Medium size, the main photo pictures no known size" do
      product = generate(product(photo_slugs: ["main.jpg"]))
      generate(product_variant(product_id: product.id, size: :small, own_photo_slug: nil))
      generate(product_variant(product_id: product.id, size: :large, own_photo_slug: nil))

      assert Ash.load!(product, :pictured_sizes).pictured_sizes == %{}
    end

    test "hidden photos stay among its photos and never include the main one" do
      product = generate(product(photo_slugs: ["a.jpg", "b.jpg", "c.jpg"]))

      assert update!(product, %{hidden_photo_slugs: ["a.jpg", "b.jpg", "z.jpg"]}).hidden_photo_slugs == ["b.jpg"]

      product = update!(product, %{hidden_photo_slugs: ["b.jpg", "c.jpg"]})
      product = update!(product, %{photo_slugs: ["b.jpg", "a.jpg"]})
      assert product.hidden_photo_slugs == []
    end
  end

  describe "a product's slug" do
    test "is made from the English name, without accents or punctuation" do
      assert generate(product(name: "Vårens Rosé  Bukett!")).slug == "varens-rose-bukett"
    end

    test "is the one typed in the form, made URL-shaped" do
      assert generate(product(name: "Red roses", slug: "Röda Rosor")).slug == "roda-rosor"
    end

    test "gets -2 when another product already has it" do
      generate(product(name: "Rosé"))
      assert generate(product(name: "Rose")).slug == "rose-2"
    end

    test "stays put when the product is renamed" do
      product = generate(product(name: "Red roses"))
      assert update!(product, %{name: "Crimson roses"}).slug == "red-roses"
    end

    test "edited, sends links with the old slug and the id to the new one" do
      product = generate(product(name: "Red roses"))
      product = update!(product, %{slug: "roses"})

      assert Catalog.current_product_slug!("red-roses") == "roses"
      assert Catalog.current_product_slug!(product.id) == "roses"
      assert Catalog.current_product_slug!("roses") == nil
    end

    test "a 16-character former slug still redirects" do
      product = generate(product(name: "Spring workshops"))
      update!(product, %{slug: "workshops"})

      assert Catalog.current_product_slug!("spring-workshops") == "workshops"
    end

    test "edited from a form opened before another edit, remembers every earlier slug" do
      stale = generate(product(name: "Roses"))
      update!(stale, %{slug: "red-roses"})

      assert update!(stale, %{slug: "summer-roses"}).slug == "summer-roses"
      assert Catalog.current_product_slug!("roses") == "summer-roses"
      assert Catalog.current_product_slug!("red-roses") == "summer-roses"
    end

    for slug_input <- [:omitted, :unchanged, :normalized] do
      test "a stale unrelated save preserves redirects with #{slug_input} slug input" do
        stale = generate(product(name: "Roses"))
        update!(stale, %{slug: "red-roses"})
        params = %{name: "Crimson roses"}

        params =
          case unquote(slug_input) do
            :omitted -> params
            :unchanged -> Map.put(params, :slug, stale.slug)
            :normalized -> Map.put(params, :slug, "Röses!")
          end

        update!(stale, params)

        assert Catalog.current_product_slug!(stale.id) == "red-roses"
        assert Catalog.current_product_slug!("roses") == "red-roses"
        assert Catalog.current_product_slug!("red-roses") == nil
      end
    end

    test "a former slug stays with its product" do
      roses = generate(product(name: "Red roses"))
      update!(roses, %{slug: "roses"})
      tulips = generate(product(name: "Tulips"))

      assert {:error, error} = update(tulips, %{slug: "red-roses"})
      assert Exception.message(error) =~ "already taken"
      assert generate(product(name: "Red roses!")).slug == "red-roses-2"
    end

    test "a product can take back its own former slug" do
      product = generate(product(name: "Red roses"))
      product = product |> update!(%{slug: "roses"}) |> update!(%{slug: "red-roses"})

      assert product.slug == "red-roses"
      assert Catalog.current_product_slug!("roses") == "red-roses"
    end
  end

  test "only a wreath category keeps a product's bow colours" do
    wreath = generate(product(bow_colours: [:red, :blue]))
    assert wreath.bow_colours == [:red, :blue]

    bouquets = generate(product_category())
    assert update!(wreath, %{product_category_id: bouquets.id}).bow_colours == []
  end

  test "a wreath is never a subscription, as its later deliveries couldn't carry the bow" do
    wreaths = generate(product_category(product_type: :wreath))
    bouquet = generate(product(subscribable: true))

    refute update!(bouquet, %{product_category_id: wreaths.id}).subscribable
    refute update!(generate(product(bow_colours: [:red])), %{subscribable: true}).subscribable
  end

  defp update(product, params),
    do: product |> Ash.Changeset.for_update(:update, params) |> Ash.update(authorize?: false)

  defp update!(product, params),
    do: product |> Ash.Changeset.for_update(:update, params) |> Ash.update!(authorize?: false)
end

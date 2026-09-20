defmodule Edenflowers.TranslationsTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Translations

  describe "translate/2" do
    test "returns the locale's translation when one exists" do
      product =
        generate(
          product(
            name: "Red Roses",
            translations: %{fi: %{name: "Punaiset ruusut"}}
          )
        )

      assert %{name: "Punaiset ruusut"} = Translations.translate(product, :fi)
    end

    test "falls back to the default locale for an untranslated field" do
      product =
        generate(
          product(
            name: "Red Roses",
            description: "A dozen stems",
            translations: %{fi: %{name: "Punaiset ruusut"}}
          )
        )

      translated = Translations.translate(product, :fi)

      assert translated.name == "Punaiset ruusut"
      # :description has no :fi entry, so en-GB must show rather than nil
      assert translated.description == "A dozen stems"
    end

    test "falls back for a locale with no translations at all" do
      product = generate(product(name: "Red Roses", translations: %{fi: %{name: "Punaiset ruusut"}}))

      assert %{name: "Red Roses"} = Translations.translate(product, :"sv-FI")
    end

    test "translates a list in one pass, and passes nil and [] through" do
      generate(product(name: "Red Roses", translations: %{fi: %{name: "Punaiset ruusut"}}))
      generate(product(name: "Tulips", translations: %{fi: %{name: "Tulppaanit"}}))

      names =
        Edenflowers.Catalog.Product
        |> Ash.read!(authorize?: false)
        |> Translations.translate(:fi)
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert names == ["Punaiset ruusut", "Tulppaanit"]
      assert Translations.translate(nil, :fi) == nil
      assert Translations.translate([], :fi) == []
    end
  end

  describe "translate_assoc/2" do
    test "translates a nested belongs_to on each record" do
      product = generate(product(name: "Gift Card", translations: %{fi: %{name: "Lahjakortti"}}))
      generate(product_variant(product_id: product.id))

      variants =
        Edenflowers.Catalog.ProductVariant
        |> Ash.read!(authorize?: false, load: [:product])
        |> Translations.translate_assoc(:product, :fi)

      assert [%{product: %{name: "Lahjakortti"}}] = variants
    end
  end
end

defmodule Edenflowers.TranslationsTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Translations

  test "translates a field, falling back to the default locale for missing ones" do
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
    assert translated.description == "A dozen stems"
    assert %{name: "Red Roses"} = Translations.translate(product, :"sv-FI")
    assert Translations.translate(nil, :fi) == nil
    assert Translations.translate([], :fi) == []
  end

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

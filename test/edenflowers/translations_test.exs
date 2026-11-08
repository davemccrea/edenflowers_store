defmodule Edenflowers.TranslationsTest do
  use Edenflowers.DataCase, async: true

  require Ash.Query

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

  test "reuses loaded translations for a record and a list without querying" do
    product = generate(product(name: "Gift Card", translations: %{fi: %{name: "Lahjakortti"}}))
    untranslated = generate(product(name: "Roses", translations: %{}))
    ref = watch_queries()

    assert %{name: "Lahjakortti"} = Translations.translate(product, :fi)
    assert [%{name: "Lahjakortti"}, %{name: "Roses"}] = Translations.translate([product, untranslated], :fi)
    refute_received ^ref
  end

  test "loads unselected translations in one batch, keeping the records in order" do
    product = generate(product(name: "Gift Card", translations: %{fi: %{name: "Lahjakortti"}}))
    other = generate(product(name: "Roses", translations: %{fi: %{name: "Ruusut"}}))

    unselected =
      Edenflowers.Catalog.Product
      |> Ash.Query.select([:id, :name])
      |> Ash.Query.filter(id == ^product.id)
      |> Ash.read_one!(authorize?: false)

    refute Ash.Resource.loaded?(unselected, :translations)
    ref = watch_queries()

    assert %{name: "Lahjakortti"} = Translations.translate(unselected, :fi)
    assert_received ^ref
    refute_received ^ref

    assert [%{name: "Ruusut"}, %{name: "Lahjakortti"}] = Translations.translate([other, unselected], :fi)
    assert_received ^ref
    refute_received ^ref
  end

  defp watch_queries do
    ref = make_ref()

    :ok =
      :telemetry.attach(
        ref,
        [:edenflowers, :repo, :query],
        fn _event, _measurements, _metadata, owner ->
          if self() == owner, do: send(owner, ref)
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end
end

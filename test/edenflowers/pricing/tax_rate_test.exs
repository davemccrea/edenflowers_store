defmodule Edenflowers.Pricing.TaxRateTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Catalog
  alias Edenflowers.Pricing

  test "a retired rate stays on what uses it but is no longer selectable" do
    retired = generate(tax_rate())
    current = generate(tax_rate())
    product = generate(product(tax_rate_id: retired.id))

    Pricing.retire_tax_rate!(retired, authorize?: false)

    assert Catalog.get_product_by_id!(product.id, load: [:tax_rate], authorize?: false).tax_rate.id == retired.id
    assert [%{id: id}] = Pricing.list_selectable_tax_rates!(authorize?: false)
    assert id == current.id
  end

  test "the standard rate is listed first, so admin forms default to it" do
    generate(tax_rate(name: "Reduced 13.5%", percentage: "0.135"))
    standard = generate(tax_rate(name: "Standard 25.5%", percentage: "0.255"))

    assert [%{id: id}, _] = Pricing.list_selectable_tax_rates!(authorize?: false)
    assert id == standard.id
  end

  test "a rate still in use can't be destroyed" do
    tax_rate = generate(tax_rate())
    generate(product(tax_rate_id: tax_rate.id))

    assert {:error, _} = Ash.destroy(tax_rate, authorize?: false)
  end

  test "a rate's percentage can be edited" do
    tax_rate = generate(tax_rate(percentage: "0.24"))

    assert {:ok, %{percentage: percentage}} = Ash.update(tax_rate, %{percentage: "0.255"}, authorize?: false)
    assert Decimal.equal?(percentage, "0.255")
  end
end

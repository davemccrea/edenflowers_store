defmodule Edenflowers.FormatTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Format

  describe "storefront_price/2" do
    test "drops the cents on whole euros" do
      assert Format.storefront_price(Decimal.new("45.00"), "en-GB") == "€45"
      assert Format.storefront_price(1500, "en-GB") == "€1,500"
    end

    test "keeps the cents otherwise" do
      assert Format.storefront_price(Decimal.new("45.50"), "en-GB") == "€45.50"
    end
  end
end

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

  describe "Finnish and Swedish dates" do
    test "use each language's own date grammar, whether the locale is an atom or a string" do
      for locale <- [:fi, "fi"] do
        assert Format.weekday_date(~D[2026-06-08], locale) == "maanantaina 8. kesäkuuta"
        assert Format.weekday_day_month(~D[2026-06-08], locale) == "maanantai 8.6."
        assert Format.day_month(~D[2026-06-08], locale) == "8.6."
        assert Format.weekday_name(:monday, locale) == "maanantai"
      end

      for locale <- [:"sv-FI", "sv-FI"] do
        assert Format.weekday_date(~D[2026-06-08], locale) == "måndag den 8 juni"
      end
    end
  end
end

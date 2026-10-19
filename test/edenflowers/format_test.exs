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

  describe "dates" do
    test "use the Finnish numeric style in every language" do
      date = ~D[2026-06-08]

      assert Format.date(date, "en-GB") == "8.6.2026"
      assert Format.weekday_date(date, "en-GB") == "Monday 8.6.2026"
      assert Format.weekday_day_month(date, "en-GB") == "Monday 8.6."
      assert Format.day_month(date, "en-GB") == "8.6."

      assert Format.weekday_date(date, "sv-FI") == "måndag 8.6.2026"
      assert Format.datetime(~U[2026-06-08 09:30:00Z], "en-GB") == "8.6.2026 12:30"
    end

    test "put the Finnish weekday in the essive in prose and in the nominative in labels" do
      for locale <- [:fi, "fi"] do
        assert Format.weekday_date(~D[2026-06-08], locale) == "maanantaina 8.6.2026"
        assert Format.weekday_day_month(~D[2026-06-08], locale) == "maanantai 8.6."
        assert Format.weekday_name(:monday, locale) == "maanantai"
      end
    end
  end
end

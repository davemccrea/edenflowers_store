defmodule Edenflowers.Orders.ReceiptTest do
  # build_payload/1 is pure — no DB needed.
  use ExUnit.Case, async: true

  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Orders.{LineItem, Order}

  # Structural diff against the fixtures — catches missing keys / nullability drift without coupling to arithmetic.
  @sample_dir Path.join([:code.priv_dir(:edenflowers), "receipts", "sample"])

  describe "build_payload/1" do
    test "matches the order.en.json fixture shape for a delivery order" do
      order = build_delivery_order(locale: "en-GB")
      payload = Receipt.build_payload(order)
      fixture = read_fixture("order.en.json")

      assert_same_keys(payload, fixture)
      assert_same_line_item_keys(payload, fixture)
      assert payload.fulfillment_method == "delivery"
      assert payload.lang == "en"
    end

    test "matches the order.en.pickup.json fixture shape for a pickup order" do
      order = build_pickup_order(locale: "en-GB")
      payload = Receipt.build_payload(order)
      fixture = read_fixture("order.en.pickup.json")

      assert_same_keys(payload, fixture)
      assert payload.fulfillment_method == "pickup"
      # Keys must be present on the payload even when null — the template asserts presence.
      assert payload.recipient_name == nil
      assert payload.delivery_address == nil
      assert payload.delivery_instructions == nil
      # Mandatory for pickup (order.ex) so Jennie can text when it's ready.
      assert payload.recipient_phone_number == "+358 40 555 0123"
    end

    test "carries the order locale into the payload language code" do
      assert Receipt.build_payload(build_delivery_order(locale: "fi")).lang == "fi"
      assert Receipt.build_payload(build_delivery_order(locale: "sv-FI")).lang == "sv"
      assert Receipt.build_payload(build_delivery_order(locale: "en-GB")).lang == "en"
    end

    test "uses fi locale conventions for currency and percentage" do
      order = build_delivery_order(locale: "fi")
      payload = Receipt.build_payload(order)

      # NBSP (U+00A0) doesn't match \s in default mode.
      assert payload.items_subtotal =~ ~r/\d+,\d{2}\x{00A0}€/u

      [line | _] = payload.line_items
      assert line.tax_rate =~ ~r/25,5\x{00A0}%/u
    end

    test "names the weekday alongside the fulfillment date" do
      # The weekday is the part the customer acts on. CLDR lowercases it in fi/sv,
      # and Finnish puts it in the essive ("lauantaina") next to a date — both correct.
      assert Receipt.build_payload(build_delivery_order(locale: "fi")).fulfillment_date ==
               "lauantaina 16.5.2026"

      assert Receipt.build_payload(build_delivery_order(locale: "en-GB")).fulfillment_date ==
               "Saturday 16/05/2026"
    end

    test "renders tax_rate with a single fractional digit" do
      # Default :percent rounds 25.5% to "26%" — regression guard for Format.percentage.
      order = build_delivery_order(locale: "en-GB")
      [line | _] = Receipt.build_payload(order).line_items

      assert line.tax_rate =~ "25.5"
    end

    test "renders discount as null when no promotion is applied" do
      order = build_delivery_order(locale: "en-GB", with_promotion: false)
      payload = Receipt.build_payload(order)

      assert payload.discount == nil
    end

    test "renders discount as a formatted string when a promotion is applied" do
      order = build_delivery_order(locale: "en-GB", with_promotion: true)
      payload = Receipt.build_payload(order)

      assert is_binary(payload.discount)
      assert payload.discount =~ ~r/€/
    end

    test "states the pre-discount subtotal so the totals column balances" do
      # items_subtotal is net of the promotion and grand_total never subtracts it,
      # so printing it raw next to a Discount row double-counts the discount.
      payload = Receipt.build_payload(build_delivery_order(locale: "en-GB", with_promotion: true))

      # 56.90 goods − 5.69 discount + 9.00 fee = 60.21
      assert payload.items_subtotal == "€56.90"
      assert payload.discount == "€5.69"
      assert payload.fulfillment_fee == "€9.00"
      assert payload.grand_total == "€60.21"
    end

    test "line item totals sum to the subtotal row above them" do
      payload = Receipt.build_payload(build_delivery_order(locale: "en-GB", with_promotion: true))

      assert payload.line_items |> Enum.map(& &1.total) |> Enum.map(&parse_eur/1) |> Enum.sum() ==
               parse_eur(payload.items_subtotal)
    end

    test "breaks VAT down per rate, taking it as contained in the tax-inclusive price" do
      order =
        build_delivery_order(
          locale: "en-GB",
          line_items: [
            {"Spring Posy", :medium, "39.90", 1, "0.255"},
            {"Chocolates", nil, "12.00", 1, "0.14"}
          ]
        )

      # 25.5%: 39.90 goods + 9.00 fee = 48.90 gross → 38.96 net, 9.94 VAT.
      # 14%:   12.00 gross → 10.53 net, 1.47 VAT.  Never gross × rate.
      assert [standard, reduced] = Receipt.build_payload(order).vat_breakdown

      assert standard == %{rate: "25.5%", base: "€38.96", tax: "€9.94", gross: "€48.90"}
      assert reduced == %{rate: "14.0%", base: "€10.53", tax: "€1.47", gross: "€12.00"}
    end

    test "each VAT row's net and tax add up to its gross" do
      order = build_delivery_order(locale: "en-GB", with_promotion: true)

      for row <- Receipt.build_payload(order).vat_breakdown do
        assert parse_eur(row.base) + parse_eur(row.tax) == parse_eur(row.gross)
      end
    end

    test "the VAT breakdown accounts for the whole grand total" do
      payload = Receipt.build_payload(build_delivery_order(locale: "en-GB", with_promotion: true))

      assert payload.vat_breakdown |> Enum.map(&parse_eur(&1.gross)) |> Enum.sum() ==
               parse_eur(payload.grand_total)
    end

    test "omits a zero fulfillment fee rather than printing a 0,00 row" do
      assert Receipt.build_payload(build_pickup_order(locale: "en-GB")).fulfillment_fee == nil
      assert Receipt.build_payload(build_delivery_order(locale: "en-GB")).fulfillment_fee == "€9.00"
    end

    test "uses customer-typed delivery_address, never the geocoded one" do
      order =
        build_delivery_order(
          locale: "en-GB",
          delivery_address: "Customer typed this",
          geocoded_address: "HERE normalised that"
        )

      assert Receipt.build_payload(order).delivery_address == "Customer typed this"
    end

    test "formats the LineItem.unit_price_ex_tax calculation as locale currency" do
      order = build_delivery_order(locale: "en-GB")
      [payload_first | _] = Receipt.build_payload(order).line_items

      assert payload_first.unit_price_ex_tax =~ "31.79"
    end
  end

  describe "generate/1" do
    @describetag :typst

    test "renders a non-empty PDF binary" do
      order = build_delivery_order(locale: "en-GB")

      assert {:ok, pdf} = Receipt.generate(order)
      assert is_binary(pdf)
      # PDF files start with the "%PDF-" magic bytes.
      assert <<"%PDF-", _rest::binary>> = pdf
    end
  end

  # Mirrors the LineItem/Order calculations so the fixture money adds up — the
  # receipt's whole job is columns that balance, and hand-picked totals can't
  # catch a receipt that double-counts.
  defp build_line_item({name, size, price, quantity, rate}, discount_rate) do
    price = Decimal.new(price)
    rate = Decimal.new(rate)
    subtotal = Decimal.mult(price, quantity)
    discount = Decimal.mult(subtotal, discount_rate)

    %LineItem{
      product_name: name,
      variant_size: size,
      quantity: quantity,
      unit_price: price,
      unit_price_ex_tax: Decimal.div(price, Decimal.add(1, rate)),
      tax_rate: rate,
      subtotal: subtotal,
      discount: discount,
      total: Decimal.sub(subtotal, discount)
    }
  end

  defp sum(line_items, field) do
    line_items |> Enum.map(&Map.fetch!(&1, field)) |> Enum.reduce(&Decimal.add/2)
  end

  defp build_order(line_items, fee, attrs) do
    items_subtotal = sum(line_items, :total)

    struct!(
      %Order{
        locale: "en-GB",
        ordered_at: ~U[2026-05-13 14:32:00Z],
        customer_name: "Anna Lindqvist",
        customer_email: "anna.lindqvist@example.fi",
        fulfillment_date: ~D[2026-05-16],
        fulfillment_fee: fee,
        fulfillment_tax_percentage: Decimal.new("0.255"),
        recipient_name: nil,
        recipient_phone_number: nil,
        delivery_address: nil,
        geocoded_address: nil,
        delivery_instructions: nil,
        card_message: nil,
        promotion_applied?: Decimal.compare(sum(line_items, :discount), 0) == :gt,
        discount: sum(line_items, :discount),
        items_subtotal: items_subtotal,
        grand_total: Decimal.add(items_subtotal, fee),
        line_items: line_items
      },
      attrs
    )
  end

  defp build_delivery_order(opts) do
    discount_rate =
      if Keyword.get(opts, :with_promotion, false), do: Decimal.new("0.10"), else: Decimal.new("0")

    line_items =
      Enum.map(
        Keyword.get(opts, :line_items, [
          {"Spring Posy", :medium, "39.90", 1, "0.255"},
          {"Eucalyptus Bunch", nil, "8.50", 2, "0.255"}
        ]),
        &build_line_item(&1, discount_rate)
      )

    line_items
    |> build_order(Decimal.new("9.00"),
      locale: Keyword.fetch!(opts, :locale),
      order_reference: "TEST-001",
      fulfillment_method: :delivery,
      recipient_name: "Margareta Lindqvist",
      recipient_phone_number: "+358 40 555 0123",
      delivery_address: "Raw Street 1",
      geocoded_address: Keyword.get(opts, :geocoded_address, "Korsholmsesplanaden 12 A 4, 65100 Vaasa"),
      delivery_instructions: "Doorbell to top-floor flat.",
      card_message: "Grattis på födelsedagen, mamma!"
    )
    |> apply_overrides(opts)
  end

  defp build_pickup_order(opts) do
    [{"Spring Posy", :medium, "39.90", 1, "0.255"}]
    |> Enum.map(&build_line_item(&1, Decimal.new("0")))
    |> build_order(Decimal.new("0"),
      locale: Keyword.fetch!(opts, :locale),
      order_reference: "TEST-002",
      ordered_at: ~U[2026-05-13 16:08:00Z],
      fulfillment_method: :pickup,
      recipient_phone_number: "+358 40 555 0123"
    )
  end

  defp apply_overrides(order, opts) do
    fields = [:geocoded_address, :delivery_address]

    Enum.reduce(fields, order, fn field, acc ->
      case Keyword.fetch(opts, field) do
        {:ok, value} -> Map.put(acc, field, value)
        :error -> acc
      end
    end)
  end

  # Cents, so the balance assertions compare what the customer actually reads
  # rather than the unrounded Decimals behind it.
  defp parse_eur(formatted) do
    formatted
    |> String.replace(~r/[^0-9,.\-]/u, "")
    |> String.replace(",", ".")
    |> Decimal.new()
    |> Decimal.mult(100)
    |> Decimal.round()
    |> Decimal.to_integer()
  end

  defp read_fixture(name) do
    @sample_dir |> Path.join(name) |> File.read!() |> Jason.decode!()
  end

  defp assert_same_keys(payload, fixture) do
    payload_keys = payload |> Map.keys() |> Enum.map(&to_string/1) |> MapSet.new()
    fixture_keys = fixture |> Map.keys() |> MapSet.new()

    missing = MapSet.difference(fixture_keys, payload_keys)
    extra = MapSet.difference(payload_keys, fixture_keys)

    assert MapSet.size(missing) == 0,
           "payload missing keys present in fixture: #{inspect(MapSet.to_list(missing))}"

    assert MapSet.size(extra) == 0,
           "payload has keys not in fixture: #{inspect(MapSet.to_list(extra))}"
  end

  defp assert_same_line_item_keys(payload, fixture) do
    [payload_item | _] = payload.line_items
    [fixture_item | _] = fixture["line_items"]

    payload_keys = payload_item |> Map.keys() |> Enum.map(&to_string/1) |> MapSet.new()
    fixture_keys = fixture_item |> Map.keys() |> MapSet.new()

    assert MapSet.equal?(payload_keys, fixture_keys),
           "line_item keys diverge: payload=#{inspect(MapSet.to_list(payload_keys))}, fixture=#{inspect(MapSet.to_list(fixture_keys))}"
  end
end

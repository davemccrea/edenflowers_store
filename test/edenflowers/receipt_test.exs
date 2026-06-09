defmodule Edenflowers.ReceiptTest do
  # build_payload/1 is pure — no DB needed.
  use ExUnit.Case, async: true

  alias Edenflowers.Receipt
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
      assert payload.recipient_phone_number == nil
      assert payload.delivery_address == nil
      assert payload.delivery_instructions == nil
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

  defp build_delivery_order(opts) do
    locale = Keyword.fetch!(opts, :locale)
    with_promotion = Keyword.get(opts, :with_promotion, false)

    %Order{
      locale: locale,
      order_reference: "EF-TEST-001",
      ordered_at: ~U[2026-05-13 14:32:00Z],
      customer_name: "Anna Lindqvist",
      customer_email: "anna.lindqvist@example.fi",
      fulfillment_method: :delivery,
      fulfillment_date: ~D[2026-05-16],
      fulfillment_fee: Decimal.new("9.00"),
      recipient_name: "Margareta Lindqvist",
      recipient_phone_number: "+358 40 555 0123",
      delivery_address: "Raw Street 1",
      geocoded_address: Keyword.get(opts, :geocoded_address, "Korsholmsesplanaden 12 A 4, 65100 Vaasa"),
      delivery_instructions: "Doorbell to top-floor flat.",
      card_message: "Grattis på födelsedagen, mamma!",
      promotion_applied?: with_promotion,
      discount: if(with_promotion, do: Decimal.new("6.14"), else: Decimal.new("0")),
      items_subtotal: Decimal.new("61.40"),
      tax: Decimal.new("13.38"),
      grand_total: Decimal.new("64.26"),
      line_items: [
        %LineItem{
          product_name: "Spring Posy",
          variant_size: :medium,
          quantity: 1,
          unit_price: Decimal.new("39.90"),
          unit_price_ex_tax: Decimal.new("31.79"),
          tax_rate: Decimal.new("0.255"),
          total: Decimal.new("39.90")
        },
        %LineItem{
          product_name: "Eucalyptus Bunch",
          variant_size: nil,
          quantity: 2,
          unit_price: Decimal.new("8.50"),
          unit_price_ex_tax: Decimal.new("6.77"),
          tax_rate: Decimal.new("0.255"),
          total: Decimal.new("17.00")
        }
      ]
    }
    |> apply_overrides(opts)
  end

  defp build_pickup_order(opts) do
    locale = Keyword.fetch!(opts, :locale)

    %Order{
      locale: locale,
      order_reference: "EF-TEST-002",
      ordered_at: ~U[2026-05-13 16:08:00Z],
      customer_name: "Anna Lindqvist",
      customer_email: "anna.lindqvist@example.fi",
      fulfillment_method: :pickup,
      fulfillment_date: ~D[2026-05-16],
      fulfillment_fee: Decimal.new("0"),
      recipient_name: nil,
      recipient_phone_number: nil,
      delivery_address: nil,
      geocoded_address: nil,
      delivery_instructions: nil,
      card_message: nil,
      promotion_applied?: false,
      discount: Decimal.new("0"),
      items_subtotal: Decimal.new("48.40"),
      tax: Decimal.new("9.84"),
      grand_total: Decimal.new("48.40"),
      line_items: [
        %LineItem{
          product_name: "Spring Posy",
          variant_size: :medium,
          quantity: 1,
          unit_price: Decimal.new("39.90"),
          unit_price_ex_tax: Decimal.new("31.79"),
          tax_rate: Decimal.new("0.255"),
          total: Decimal.new("39.90")
        }
      ]
    }
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

defmodule Edenflowers.Payments.VirtualBarcodeTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Payments.VirtualBarcode

  # The version 4 test invoices in Finance Finland's Bank Bar Code Guide 5.3,
  # section 13.1, as the guide prints them: Code C value pairs between the
  # start character and the check digit. Invoice 5 has no due date, which an
  # invoice here always has.
  @examples [
    {"FI79 4405 2020 0360 82", "4883.15", "86851 62596 19897", ~D[2010-06-12],
     "47 94 40 52 02 00 36 08 20 04 88 31 50 00 00 00 08 68 51 62 59 61 98 97 10 06 12"},
    {"FI58 1017 1000 0001 22", "482.99", "55958 22432 94671", ~D[2012-01-31],
     "45 81 01 71 00 00 00 12 20 00 48 29 90 00 00 00 05 59 58 22 43 29 46 71 12 01 31"},
    {"FI02 5000 4640 0013 02", "693.80", "69 87567 20834 35364", ~D[2011-07-24],
     "40 25 00 04 64 00 01 30 20 00 69 38 00 00 00 06 98 75 67 20 83 43 53 64 11 07 24"},
    {"FI15 6601 0001 5306 41", "7444.54", "7 75847 47906 47489", ~D[2019-12-19],
     "41 56 60 10 00 15 30 64 10 07 44 45 40 00 00 00 77 58 47 47 90 64 74 89 19 12 19"},
    {"FI73 3131 3001 0000 58", "0.00", "8 68624", ~D[2013-08-09],
     "47 33 13 13 00 10 00 05 80 00 00 00 00 00 00 00 00 00 00 00 00 86 86 24 13 08 09"},
    {"FI83 3301 0001 1007 75", "150000.20", "92125 37425 25398 97737", ~D[2016-05-25],
     "48 33 30 10 00 11 00 77 51 50 00 02 00 00 92 12 53 74 25 25 39 89 77 37 16 05 25"},
    {"FI39 3636 3002 0924 92", "1.03", "5907 38390", ~D[2023-03-11],
     "43 93 63 63 00 20 92 49 20 00 00 10 30 00 00 00 00 00 00 05 90 73 83 90 23 03 11"},
    {"FI92 3939 0001 0033 91", "0.02", "13 57914", ~D[2099-12-24],
     "49 23 93 90 00 10 03 39 10 00 00 00 20 00 00 00 00 00 00 00 01 35 79 14 99 12 24"}
  ]

  test "matches every version 4 test invoice in the Bank Bar Code Guide" do
    for {iban, amount, reference, due_date, pairs} <- @examples do
      reference = String.replace(reference, " ", "")

      assert VirtualBarcode.version_4(iban, Decimal.new(amount), reference, due_date) ==
               String.replace(pairs, " ", "")
    end
  end

  test "matches Zervant's invoice 1336 to Jennie's account" do
    assert VirtualBarcode.version_4("FI69 3939 0018 3959 05", Decimal.new("544.00"), "13369", ~D[2026-09-27]) ==
             "469393900183959050005440000000000000000000013369260927"
  end

  test "can't carry a non-Finnish IBAN or a million euros" do
    assert_raise MatchError, fn ->
      VirtualBarcode.version_4("SE45 5000 0000 0583 9825 7466", Decimal.new("10.00"), "10009", ~D[2026-11-15])
    end

    assert_raise ArgumentError, fn ->
      VirtualBarcode.version_4("FI79 4405 2020 0360 82", Decimal.new("1000000.00"), "10009", ~D[2026-11-15])
    end
  end
end

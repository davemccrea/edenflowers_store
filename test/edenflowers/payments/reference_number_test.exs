defmodule Edenflowers.Payments.ReferenceNumberTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Payments.ReferenceNumber

  # Finance Finland's worked example in "Forming a Finnish reference number".
  test "matches Finance Finland's example: stem 123456 gives 12 34561" do
    assert ReferenceNumber.from_invoice_number(123_456) == "1234561"
    assert ReferenceNumber.format("1234561") == "12 34561"
  end

  test "appends the Finnish 7-3-1 check digit" do
    assert ReferenceNumber.from_invoice_number(123) == "1232"
    assert ReferenceNumber.from_invoice_number(1_234_567) == "12345672"
    # A sum already on a multiple of ten checks with 0.
    assert ReferenceNumber.from_invoice_number(130) == "1300"
  end

  test "refuses an invoice number too short for a reference" do
    assert_raise FunctionClauseError, fn -> ReferenceNumber.from_invoice_number(99) end
  end

  test "every reference it makes passes the check, and a changed digit fails it" do
    for number <- 100..3000, do: assert(ReferenceNumber.valid?(ReferenceNumber.from_invoice_number(number)))
    refute ReferenceNumber.valid?("1233")
    refute ReferenceNumber.valid?("01232")
  end

  test "groups the digits in fives from the right" do
    assert ReferenceNumber.format("12345672") == "123 45672"
    assert ReferenceNumber.format("1232") == "1232"
  end
end

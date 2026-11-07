defmodule Edenflowers.Orders.PaymentInstructionTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Orders.Order

  defp instruction(resource, refs) do
    {:ok, instruction} = Ash.calculate(resource, :payment_instruction, refs: Map.new(refs))
    instruction
  end

  test "an order's payment link takes precedence over its terms, and paid orders need no instruction" do
    assert instruction(Order, unpaid?: true, payment_link_open?: true, payment_terms: :invoice) == :pay_now
    assert instruction(Order, unpaid?: false, payment_link_open?: true, payment_terms: :invoice) == nil
    assert instruction(Order, unpaid?: true, payment_link_open?: false, payment_terms: :invoice) == :invoice
    assert instruction(Order, unpaid?: true, payment_link_open?: false, payment_terms: nil) == nil
  end

  test "an order stops asking for payment in person once delivered or collected" do
    for {method, expected} <- [delivery: :on_delivery, pickup: :at_collection] do
      refs = [
        unpaid?: true,
        payment_link_open?: false,
        payment_terms: :on_fulfillment,
        fulfillment_method: method,
        fulfillment_status: :pending
      ]

      assert instruction(Order, refs) == expected
      assert instruction(Order, Keyword.put(refs, :fulfillment_status, :fulfilled)) == nil
    end
  end

  test "course invoices take precedence over payment links, with payment at the course as the fallback" do
    assert instruction(CourseRegistration, balance: Decimal.new(60), payment_terms: :invoice, payment_link_open?: true) ==
             :invoice

    assert instruction(CourseRegistration,
             balance: Decimal.new(60),
             payment_terms: :payment_link,
             payment_link_open?: true
           ) == :pay_now

    assert instruction(CourseRegistration,
             balance: Decimal.new(60),
             payment_terms: :on_fulfillment,
             payment_link_open?: false
           ) == :at_course

    assert instruction(CourseRegistration, balance: Decimal.new(0), payment_terms: :invoice, payment_link_open?: true) ==
             nil
  end
end

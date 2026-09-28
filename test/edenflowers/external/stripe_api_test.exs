defmodule Edenflowers.External.StripeAPITest do
  use ExUnit.Case, async: true

  alias Edenflowers.External.StripeAPI

  test "converts amounts to and from Stripe cents" do
    assert StripeAPI.to_stripe_amount(Decimal.new("45.50")) == 4550
    assert StripeAPI.from_stripe_amount(4550) == Decimal.new("45.50")
    assert StripeAPI.from_stripe_amount(4500) == Decimal.new("45.00")
  end
end

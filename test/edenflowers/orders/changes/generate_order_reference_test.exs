defmodule Edenflowers.Orders.Changes.GenerateOrderReferenceTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Orders.Changes.GenerateOrderReference

  test "generates six-character Crockford Base32 references" do
    for _ <- 1..100 do
      reference = GenerateOrderReference.generate()

      assert reference =~ ~r/^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{6}$/
      refute reference =~ ~r/[ILOU]/
    end
  end
end

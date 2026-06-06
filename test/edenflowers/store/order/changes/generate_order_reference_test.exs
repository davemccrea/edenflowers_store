defmodule Edenflowers.Store.Order.Changes.GenerateOrderReferenceTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Store.Order.Changes.GenerateOrderReference

  test "generates six-character Crockford Base32 references" do
    for _ <- 1..100 do
      reference = GenerateOrderReference.generate()

      assert reference =~ ~r/^EF-[0-9ABCDEFGHJKMNPQRSTVWXYZ]{6}$/
      refute reference =~ ~r/[ILOU]/
    end
  end
end

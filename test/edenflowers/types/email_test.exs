defmodule Edenflowers.Types.EmailTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Types.Email

  test "accepts an address and trims surrounding whitespace" do
    assert {:ok, "jennie@example.com"} = Ash.Type.cast_input(Email, "  jennie@example.com ")
  end

  test "rejects an address without an @" do
    assert {:error, message: "Must be a valid email address"} = Ash.Type.cast_input(Email, "jennie.example.com")
  end

  test "rejects an address without a dot after the @" do
    assert {:error, message: "Must be a valid email address"} = Ash.Type.cast_input(Email, "jennie@example")
  end
end

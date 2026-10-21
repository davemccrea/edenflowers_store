defmodule Edenflowers.Accounts.Calculations.LastNameTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Accounts.Calculations.LastName

  test "extracts everything after the first name" do
    assert LastName.extract("Jane Doe") == "Doe"
    assert LastName.extract("  Jan   van der Berg ") == "van der Berg"
    assert LastName.extract("Smith, Jane") == "Smith"
  end

  test "is nil without a family name" do
    assert LastName.extract("Madonna") == nil
    assert LastName.extract(", Jane") == nil
    assert LastName.extract("   ") == nil
    assert LastName.extract(nil) == nil
  end
end

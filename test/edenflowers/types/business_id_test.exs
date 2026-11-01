defmodule Edenflowers.Types.BusinessIdTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Types.BusinessId

  @message "Must be a valid Y-tunnus, such as 1234567-8"

  test "accepts a Y-tunnus with its check digit, trimmed" do
    assert {:ok, "2944459-6"} = Ash.Type.cast_input(BusinessId, " 2944459-6 ")
  end

  test "accepts a check digit of 0 when the weighted sum divides by 11" do
    assert {:ok, "0000000-0"} = Ash.Type.cast_input(BusinessId, "0000000-0")
  end

  test "rejects a wrong check digit" do
    assert {:error, message: @message} = Ash.Type.cast_input(BusinessId, "2944459-5")
  end

  test "rejects a Y-tunnus whose remainder is 1, which is never issued" do
    # 0000006 weighs 6 * 2 = 12, leaving a remainder of 1.
    for check <- 0..9 do
      assert {:error, message: @message} = Ash.Type.cast_input(BusinessId, "0000006-#{check}")
    end
  end

  test "rejects the wrong shape" do
    for value <- ["29444596", "294445-6", "2944459-66", "ABCDEFG-1"] do
      assert {:error, message: @message} = Ash.Type.cast_input(BusinessId, value)
    end
  end
end

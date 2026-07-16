defmodule Edenflowers.Fulfillment.FulfillmentOption.Changes.ResetCalendarTest do
  use ExUnit.Case, async: true
  alias Edenflowers.Fulfillment.FulfillmentOption.Changes.ResetCalendar

  describe "reset/0" do
    test "returns fully-open weekdays and empty override lists" do
      result = ResetCalendar.reset()
      assert Enum.sort(result.available_days) == [:friday, :monday, :saturday, :sunday, :thursday, :tuesday, :wednesday]
      assert result.enabled_dates == []
      assert result.disabled_dates == []
    end
  end
end

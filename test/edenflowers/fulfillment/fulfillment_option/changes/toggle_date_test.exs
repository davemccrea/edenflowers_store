defmodule Edenflowers.Fulfillment.FulfillmentOption.Changes.ToggleDateTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Fulfillment.FulfillmentOption.Changes.ToggleDate

  setup do
    tax_rate = generate(tax_rate())
    [tax_rate_id: tax_rate.id]
  end

  describe "toggle_date/2" do
    test "closes a date when its weekday is currently available", %{tax_rate_id: tax_rate_id} do
      # All weekdays available, no overrides
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      # 2024-04-10 is a Wednesday
      assert %{enabled_dates: [], disabled_dates: [~D[2024-04-10]]} =
               ToggleDate.toggle_date(option, ~D[2024-04-10])
    end

    test "opens a date when its weekday is currently disabled", %{tax_rate_id: tax_rate_id} do
      # Sunday off, no overrides
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      # 2024-04-07 is a Sunday
      assert %{enabled_dates: [~D[2024-04-07]], disabled_dates: []} =
               ToggleDate.toggle_date(option, ~D[2024-04-07])
    end

    test "removes an existing off-override", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-10]]))

      assert %{enabled_dates: [], disabled_dates: []} =
               ToggleDate.toggle_date(option, ~D[2024-04-10])
    end

    test "removes an existing on-override", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, enabled_dates: [~D[2024-04-07]]))

      assert %{enabled_dates: [], disabled_dates: []} =
               ToggleDate.toggle_date(option, ~D[2024-04-07])
    end

    test "off-override does not duplicate other off-overrides", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-15]]))

      assert %{disabled_dates: dates} = ToggleDate.toggle_date(option, ~D[2024-04-10])
      assert ~D[2024-04-15] in dates
      assert ~D[2024-04-10] in dates
    end
  end
end

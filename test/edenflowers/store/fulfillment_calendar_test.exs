defmodule Edenflowers.Store.FulfillmentCalendarTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Store.FulfillmentCalendar

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
               FulfillmentCalendar.toggle_date(option, ~D[2024-04-10])
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
               FulfillmentCalendar.toggle_date(option, ~D[2024-04-07])
    end

    test "removes an existing off-override", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-10]]))

      assert %{enabled_dates: [], disabled_dates: []} =
               FulfillmentCalendar.toggle_date(option, ~D[2024-04-10])
    end

    test "removes an existing on-override", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, enabled_dates: [~D[2024-04-07]]))

      assert %{enabled_dates: [], disabled_dates: []} =
               FulfillmentCalendar.toggle_date(option, ~D[2024-04-07])
    end

    test "off-override does not duplicate other off-overrides", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-15]]))

      assert %{disabled_dates: dates} = FulfillmentCalendar.toggle_date(option, ~D[2024-04-10])
      assert ~D[2024-04-15] in dates
      assert ~D[2024-04-10] in dates
    end
  end

  describe "toggle_weekday/2" do
    test "disables a currently-available weekday", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      %{available_days: days} = FulfillmentCalendar.toggle_weekday(option, :sunday)
      refute :sunday in days
    end

    test "enables a currently-disabled weekday", %{tax_rate_id: tax_rate_id} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      %{available_days: days} = FulfillmentCalendar.toggle_weekday(option, :sunday)
      assert :sunday in days
    end

    test "enabling a weekday prunes stale enabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # 2024-04-15 is a Monday. Start with Mondays off and an on-override.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
            enabled_dates: [~D[2024-04-15]]
          )
        )

      result = FulfillmentCalendar.toggle_weekday(option, :monday)

      assert :monday in result.available_days
      # The on-override is no longer needed — Mondays are open now.
      refute ~D[2024-04-15] in result.enabled_dates
    end

    test "enabling a weekday preserves disabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # Mondays off, with Mon 2024-04-15 in disabled_dates (redundant but present).
      # After turning Mondays on, the off-override is a genuine exception and must survive.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
            disabled_dates: [~D[2024-04-15]]
          )
        )

      result = FulfillmentCalendar.toggle_weekday(option, :monday)

      assert :monday in result.available_days
      assert ~D[2024-04-15] in result.disabled_dates
    end

    test "disabling a weekday prunes stale disabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # Mondays on, with Mon 2024-04-15 in disabled_dates as an off-override.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            disabled_dates: [~D[2024-04-15]]
          )
        )

      result = FulfillmentCalendar.toggle_weekday(option, :monday)

      refute :monday in result.available_days
      # The off-override is now redundant — Mondays are closed by rule.
      refute ~D[2024-04-15] in result.disabled_dates
    end

    test "disabling a weekday preserves enabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # Mondays on, with Mon 2024-04-15 in enabled_dates (redundant but present).
      # After turning Mondays off, the on-override is a genuine exception and must survive.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            enabled_dates: [~D[2024-04-15]]
          )
        )

      result = FulfillmentCalendar.toggle_weekday(option, :monday)

      refute :monday in result.available_days
      assert ~D[2024-04-15] in result.enabled_dates
    end

    test "weekday flip only touches overrides matching the toggled weekday", %{tax_rate_id: tax_rate_id} do
      # 2024-04-15 is Monday, 2024-04-16 is Tuesday.
      # Toggling Monday should leave Tuesday's override completely alone.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            enabled_dates: [~D[2024-04-15]],
            disabled_dates: [~D[2024-04-16]]
          )
        )

      result = FulfillmentCalendar.toggle_weekday(option, :monday)

      refute :monday in result.available_days
      assert ~D[2024-04-15] in result.enabled_dates
      assert ~D[2024-04-16] in result.disabled_dates
    end
  end

  describe "cell_state_for_options/3" do
    test "returns the single shared state when all options agree", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      today = ~D[2024-04-01]
      future_wednesday = today |> Date.shift(month: 3) |> next_weekday(:wednesday)

      assert :open == FulfillmentCalendar.cell_state_for_options([a, b], future_wednesday, today)
    end

    test "returns :mixed when options disagree", %{tax_rate_id: tax_rate_id} do
      open_option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      closed_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      today = ~D[2024-04-01]
      future_sunday = today |> Date.shift(month: 3) |> next_weekday(:sunday)

      assert :mixed ==
               FulfillmentCalendar.cell_state_for_options(
                 [open_option, closed_option],
                 future_sunday,
                 today
               )
    end

    test "returns :open for an empty options list", %{tax_rate_id: _} do
      assert :open == FulfillmentCalendar.cell_state_for_options([], ~D[2024-04-10], ~D[2024-04-01])
    end
  end

  defp next_weekday(date, weekday) do
    target = weekday_to_int(weekday)

    Stream.iterate(date, &Date.add(&1, 1))
    |> Enum.find(&(Date.day_of_week(&1) == target))
  end

  defp weekday_to_int(:monday), do: 1
  defp weekday_to_int(:tuesday), do: 2
  defp weekday_to_int(:wednesday), do: 3
  defp weekday_to_int(:thursday), do: 4
  defp weekday_to_int(:friday), do: 5
  defp weekday_to_int(:saturday), do: 6
  defp weekday_to_int(:sunday), do: 7
end

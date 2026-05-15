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
  end

  describe "cell_state_for_options/2" do
    test "returns the single shared state when all options agree", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      # Pick a date well in the future to avoid same-day edge cases.
      future_wednesday = Date.utc_today() |> Date.shift(month: 3) |> next_weekday(:wednesday)

      assert :open == FulfillmentCalendar.cell_state_for_options([a, b], future_wednesday)
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

      future_sunday = Date.utc_today() |> Date.shift(month: 3) |> next_weekday(:sunday)

      assert :mixed == FulfillmentCalendar.cell_state_for_options([open_option, closed_option], future_sunday)
    end

    test "returns :open for an empty options list", %{tax_rate_id: _} do
      assert :open == FulfillmentCalendar.cell_state_for_options([], ~D[2024-04-10])
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

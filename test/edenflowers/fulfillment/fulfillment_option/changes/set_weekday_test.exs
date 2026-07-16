defmodule Edenflowers.Fulfillment.FulfillmentOption.Changes.SetWeekdayTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Fulfillment.FulfillmentOption.Changes.SetWeekday

  setup do
    tax_rate = generate(tax_rate())
    [tax_rate_id: tax_rate.id]
  end

  describe "set_weekday/3" do
    test "setting :off removes a currently-available weekday", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      %{available_days: days} = SetWeekday.set_weekday(option, :sunday, :off)
      refute :sunday in days
    end

    test "setting :on adds a currently-disabled weekday", %{tax_rate_id: tax_rate_id} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      %{available_days: days} = SetWeekday.set_weekday(option, :sunday, :on)
      assert :sunday in days
    end

    test "is idempotent — :on on an already-on weekday is a no-op", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      %{available_days: days} = SetWeekday.set_weekday(option, :sunday, :on)
      assert Enum.sort(days) == Enum.sort(option.available_days)
    end

    test "turning a weekday :on prunes stale enabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # 2024-04-15 is a Monday. Start with Mondays off and an on-override.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
            enabled_dates: [~D[2024-04-15]]
          )
        )

      result = SetWeekday.set_weekday(option, :monday, :on)

      assert :monday in result.available_days
      # The on-override is no longer needed — Mondays are open now.
      refute ~D[2024-04-15] in result.enabled_dates
    end

    test "turning a weekday :on preserves disabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
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

      result = SetWeekday.set_weekday(option, :monday, :on)

      assert :monday in result.available_days
      assert ~D[2024-04-15] in result.disabled_dates
    end

    test "turning a weekday :off prunes stale disabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # Mondays on, with Mon 2024-04-15 in disabled_dates as an off-override.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            disabled_dates: [~D[2024-04-15]]
          )
        )

      result = SetWeekday.set_weekday(option, :monday, :off)

      refute :monday in result.available_days
      # The off-override is now redundant — Mondays are closed by rule.
      refute ~D[2024-04-15] in result.disabled_dates
    end

    test "turning a weekday :off preserves enabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # Mondays on, with Mon 2024-04-15 in enabled_dates (redundant but present).
      # After turning Mondays off, the on-override is a genuine exception and must survive.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            enabled_dates: [~D[2024-04-15]]
          )
        )

      result = SetWeekday.set_weekday(option, :monday, :off)

      refute :monday in result.available_days
      assert ~D[2024-04-15] in result.enabled_dates
    end

    test "only touches overrides matching the targeted weekday", %{tax_rate_id: tax_rate_id} do
      # 2024-04-15 is Monday, 2024-04-16 is Tuesday.
      # Setting Monday off should leave Tuesday's override completely alone.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            enabled_dates: [~D[2024-04-15]],
            disabled_dates: [~D[2024-04-16]]
          )
        )

      result = SetWeekday.set_weekday(option, :monday, :off)

      refute :monday in result.available_days
      assert ~D[2024-04-15] in result.enabled_dates
      assert ~D[2024-04-16] in result.disabled_dates
    end
  end

  describe "key-date protection" do
    # Mother's Day 2026 is a Sunday (~D[2026-05-10]).

    test "set_weekday :off preserves an open key date by adding an enabled override", %{
      tax_rate_id: tax_rate_id
    } do
      # Sundays currently on. Mother's Day is open by the rule.
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      result = SetWeekday.set_weekday(option, :sunday, :off)

      refute :sunday in result.available_days
      # Mother's Day must remain open via an enabled override.
      assert ~D[2026-05-10] in result.enabled_dates
    end

    test "set_weekday :on preserves a closed key date by adding a disabled override", %{
      tax_rate_id: tax_rate_id
    } do
      # Sundays currently off. Mother's Day is closed by the rule.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      result = SetWeekday.set_weekday(option, :sunday, :on)

      assert :sunday in result.available_days
      # Mother's Day must remain closed via a disabled override.
      assert ~D[2026-05-10] in result.disabled_dates
    end

    test "set_weekday is a no-op for the rule when direction matches current state", %{
      tax_rate_id: tax_rate_id
    } do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      result = SetWeekday.set_weekday(option, :sunday, :on)

      assert :sunday in result.available_days
      # No protection override should appear since nothing changed.
      refute ~D[2026-05-10] in result.enabled_dates
      refute ~D[2026-05-10] in result.disabled_dates
    end
  end
end

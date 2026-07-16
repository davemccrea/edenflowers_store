defmodule EdenflowersWeb.Admin.CalendarViewModelTest do
  use Edenflowers.DataCase
  import Generator
  alias EdenflowersWeb.Admin.CalendarViewModel
  alias Edenflowers.Fulfillment.Weekday

  setup do
    tax_rate = generate(tax_rate())
    [tax_rate_id: tax_rate.id]
  end

  describe "scoped_options/2" do
    test ":all returns every option", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      assert [a, b] == CalendarViewModel.scoped_options(:all, [a, b])
    end

    test "an id scope filters to that option", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      assert [b] == CalendarViewModel.scoped_options(b.id, [a, b])
    end

    test "an unknown id returns an empty list", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      assert [] == CalendarViewModel.scoped_options("missing-id", [a])
    end
  end

  describe "cell_state/4 with :all scope" do
    test "returns the single shared state when all options agree", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      today = ~D[2024-04-01]
      future_wednesday = today |> Date.shift(month: 3) |> next_weekday(:wednesday)

      assert :open == CalendarViewModel.cell_state(:all, [a, b], future_wednesday, today)
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
               CalendarViewModel.cell_state(
                 :all,
                 [open_option, closed_option],
                 future_sunday,
                 today
               )
    end

    test "returns :open for an empty options list" do
      assert :open == CalendarViewModel.cell_state(:all, [], ~D[2024-04-10], ~D[2024-04-01])
    end
  end

  describe "cell_state/4" do
    test ":all aggregates across options", %{tax_rate_id: tax_rate_id} do
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
               CalendarViewModel.cell_state(
                 :all,
                 [open_option, closed_option],
                 future_sunday,
                 today
               )
    end

    test "single-option scope returns that option's admin cell state", %{tax_rate_id: tax_rate_id} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      today = ~D[2024-04-01]
      future_sunday = today |> Date.shift(month: 3) |> next_weekday(:sunday)

      assert :weekday_disabled ==
               CalendarViewModel.cell_state(option.id, [option], future_sunday, today)
    end

    test "falls back to :open when the scoped option id is unknown", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      assert :open ==
               CalendarViewModel.cell_state("missing-id", [option], ~D[2024-04-10], ~D[2024-04-01])
    end
  end

  describe "weekday_state/3" do
    test ":all returns :on when every option has the weekday available", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      assert :on == CalendarViewModel.weekday_state(:all, [a, b], :monday)
    end

    test ":all returns :off when no option has the weekday available", %{tax_rate_id: tax_rate_id} do
      days = [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: days))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: days))

      assert :off == CalendarViewModel.weekday_state(:all, [a, b], :sunday)
    end

    test ":all returns :mixed when options disagree", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      b =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      assert :mixed == CalendarViewModel.weekday_state(:all, [a, b], :sunday)
    end

    test ":all returns :on for an empty options list" do
      # Regression: with no options, the page renders a default `:on` header.
      # Returning :mixed here previously made empty pages render with a "varies"
      # treatment despite there being nothing to vary.
      assert :on == CalendarViewModel.weekday_state(:all, [], :sunday)
    end

    test "single-option scope reads off that option", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      b =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      assert :on == CalendarViewModel.weekday_state(a.id, [a, b], :sunday)
      assert :off == CalendarViewModel.weekday_state(b.id, [a, b], :sunday)
    end

    test "single-option scope falls back to :on when the id is unknown", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      assert :on == CalendarViewModel.weekday_state("missing-id", [a], :sunday)
    end
  end

  describe "weekday_toggle_direction/2" do
    test "returns :off when any option has the weekday on", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      b =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      assert :off == CalendarViewModel.weekday_toggle_direction([a, b], :sunday)
    end

    test "returns :on when no option has the weekday on", %{tax_rate_id: tax_rate_id} do
      days = [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: days))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: days))

      assert :on == CalendarViewModel.weekday_toggle_direction([a, b], :sunday)
    end
  end

  describe "week_state/4" do
    test ":all_open when every actionable cell is open", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      # 2024-04-08 Mon .. 2024-04-14 Sun — a Mon-Sun week with no key dates.
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :all_open == CalendarViewModel.week_state(option.id, [option], week, ~D[2024-04-01])
    end

    test ":all_closed when every actionable cell is closed", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: []))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :all_closed == CalendarViewModel.week_state(option.id, [option], week, ~D[2024-04-01])
    end

    test ":mixed when some cells are open and some closed", %{tax_rate_id: tax_rate_id} do
      # Closed on Sunday only.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :mixed == CalendarViewModel.week_state(option.id, [option], week, ~D[2024-04-01])
    end

    test ":all_past when every cell is before today", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :all_past == CalendarViewModel.week_state(option.id, [option], week, ~D[2024-04-15])
    end

    test "ignores key dates so a key-date-only week reports as :all_past", %{tax_rate_id: tax_rate_id} do
      # A week where the only non-past cell is Mother's Day. The button must
      # not look actionable, since the click would no-op anyway.
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2026-05-04], &1))
      # "today" makes Mon..Sat all past, leaving only Sun (Mother's Day) actionable.
      today = ~D[2026-05-10]

      assert :all_past == CalendarViewModel.week_state(option.id, [option], week, today)
    end
  end

  describe "week_state/4 across options" do
    test ":mixed when options disagree", %{tax_rate_id: tax_rate_id} do
      open_option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      closed_option = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: []))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))

      assert :mixed ==
               CalendarViewModel.week_state(:all, [open_option, closed_option], week, ~D[2024-04-01])
    end

    test ":all_open for an empty scope" do
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :all_open == CalendarViewModel.week_state(:all, [], week, ~D[2024-04-01])
    end
  end

  describe "week_toggle_direction/3" do
    test "returns nil when no option has any actionable cell", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      # Today after the week → every cell is past.
      assert nil == CalendarViewModel.week_toggle_direction([option], week, ~D[2024-04-15])
    end

    test "returns :closed when any option has open or mixed cells", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :closed == CalendarViewModel.week_toggle_direction([option], week, ~D[2024-04-01])
    end

    test "returns :open when every option's week is fully closed", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: []))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :open == CalendarViewModel.week_toggle_direction([option], week, ~D[2024-04-01])
    end
  end

  defp next_weekday(date, weekday) do
    target = Weekday.to_integer(weekday)

    Stream.iterate(date, &Date.add(&1, 1))
    |> Enum.find(&(Date.day_of_week(&1) == target))
  end
end

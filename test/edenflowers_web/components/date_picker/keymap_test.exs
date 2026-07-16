defmodule EdenflowersWeb.DatePicker.KeymapTest do
  use ExUnit.Case, async: true

  alias EdenflowersWeb.DatePicker.Keymap

  @today ~D[2026-05-12]

  describe "next_date/3 — arrow keys" do
    test "ArrowUp moves back one week" do
      assert Keymap.next_date(~D[2026-05-15], "ArrowUp", @today) == ~D[2026-05-08]
    end

    test "ArrowDown moves forward one week" do
      assert Keymap.next_date(~D[2026-05-15], "ArrowDown", @today) == ~D[2026-05-22]
    end

    test "ArrowLeft moves back one day" do
      assert Keymap.next_date(~D[2026-05-15], "ArrowLeft", @today) == ~D[2026-05-14]
    end

    test "ArrowRight moves forward one day" do
      assert Keymap.next_date(~D[2026-05-15], "ArrowRight", @today) == ~D[2026-05-16]
    end
  end

  describe "next_date/3 — page keys (WAI-ARIA: PageUp=prev month, PageDown=next month)" do
    test "PageUp moves to previous month" do
      assert Keymap.next_date(~D[2026-06-15], "PageUp", @today) == ~D[2026-05-15]
    end

    test "PageDown moves to next month" do
      assert Keymap.next_date(~D[2026-05-15], "PageDown", @today) == ~D[2026-06-15]
    end
  end

  describe "next_date/3 — Home/End" do
    test "Home moves to start of week" do
      assert Keymap.next_date(~D[2026-05-15], "Home", @today) |> Date.day_of_week() == 1
    end

    test "End moves to end of week" do
      assert Keymap.next_date(~D[2026-05-15], "End", @today) |> Date.day_of_week() == 7
    end
  end

  describe "next_date/3 — past-month clamp" do
    test "clamps when ArrowUp would cross into the previous month" do
      assert Keymap.next_date(~D[2026-05-03], "ArrowUp", @today) == ~D[2026-05-03]
    end

    test "clamps when PageUp would cross into the previous month" do
      assert Keymap.next_date(~D[2026-05-15], "PageUp", @today) == ~D[2026-05-15]
    end

    test "does not clamp when navigating within the current month" do
      assert Keymap.next_date(~D[2026-05-15], "ArrowLeft", @today) == ~D[2026-05-14]
    end

    test "does not clamp when navigating into a future month" do
      assert Keymap.next_date(~D[2026-05-30], "ArrowDown", @today) == ~D[2026-06-06]
    end
  end

  describe "next_date/3 — unknown keys" do
    test "returns the same date" do
      assert Keymap.next_date(~D[2026-05-15], "F13", @today) == ~D[2026-05-15]
    end
  end
end

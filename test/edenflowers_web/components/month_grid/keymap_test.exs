defmodule EdenflowersWeb.MonthGrid.KeymapTest do
  use ExUnit.Case, async: true

  alias EdenflowersWeb.MonthGrid.Keymap

  @today ~D[2026-05-12]

  describe "next_date/3" do
    test "arrow keys move a day or a week" do
      assert Keymap.next_date(~D[2026-05-15], "ArrowUp", @today) == ~D[2026-05-08]
      assert Keymap.next_date(~D[2026-05-15], "ArrowDown", @today) == ~D[2026-05-22]
      assert Keymap.next_date(~D[2026-05-15], "ArrowLeft", @today) == ~D[2026-05-14]
      assert Keymap.next_date(~D[2026-05-15], "ArrowRight", @today) == ~D[2026-05-16]
    end

    test "page keys move a month (WAI-ARIA: PageUp=prev month, PageDown=next month)" do
      assert Keymap.next_date(~D[2026-06-15], "PageUp", @today) == ~D[2026-05-15]
      assert Keymap.next_date(~D[2026-05-15], "PageDown", @today) == ~D[2026-06-15]
    end

    test "Home and End jump to the week's ends" do
      assert Keymap.next_date(~D[2026-05-15], "Home", @today) |> Date.day_of_week() == 1
      assert Keymap.next_date(~D[2026-05-15], "End", @today) |> Date.day_of_week() == 7
    end

    test "clamps at the current month but allows future months" do
      assert Keymap.next_date(~D[2026-05-03], "ArrowUp", @today) == ~D[2026-05-03]
      assert Keymap.next_date(~D[2026-05-15], "PageUp", @today) == ~D[2026-05-15]
      assert Keymap.next_date(~D[2026-05-15], "ArrowLeft", @today) == ~D[2026-05-14]
      assert Keymap.next_date(~D[2026-05-30], "ArrowDown", @today) == ~D[2026-06-06]
    end

    test "unknown keys return the same date" do
      assert Keymap.next_date(~D[2026-05-15], "F13", @today) == ~D[2026-05-15]
    end
  end
end

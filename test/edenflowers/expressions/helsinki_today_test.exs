defmodule Edenflowers.Expressions.HelsinkiTodayTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Expressions.HelsinkiToday

  test "is already tomorrow in Helsinki while it is still today in UTC" do
    assert HelsinkiToday.today(~U[2026-10-07 22:30:00Z]) == ~D[2026-10-08]
    assert HelsinkiToday.today(~U[2026-01-07 21:30:00Z]) == ~D[2026-01-07]
    assert HelsinkiToday.today(~U[2026-01-07 22:30:00Z]) == ~D[2026-01-08]
  end
end

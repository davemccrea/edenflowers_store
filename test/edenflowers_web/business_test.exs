defmodule EdenflowersWeb.BusinessTest do
  use ExUnit.Case, async: true

  alias EdenflowersWeb.Business

  test "the shop has shorter opening hours on Saturday and is closed on Sunday" do
    assert Business.opening_hours(~D[2026-11-06]) == {~T[10:00:00], ~T[18:00:00]}
    assert Business.opening_hours(~D[2026-11-07]) == {~T[10:00:00], ~T[15:00:00]}
    assert Business.opening_hours(~D[2026-11-08]) == nil
  end
end

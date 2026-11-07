defmodule EdenflowersWeb.BusinessTest do
  use ExUnit.Case, async: true

  alias EdenflowersWeb.Business

  test "the shop closes earlier on Saturday and not at all on Sunday" do
    assert Business.closing_time(~D[2026-11-06]) == ~T[18:00:00]
    assert Business.closing_time(~D[2026-11-07]) == ~T[15:00:00]
    assert Business.closing_time(~D[2026-11-08]) == nil
  end
end

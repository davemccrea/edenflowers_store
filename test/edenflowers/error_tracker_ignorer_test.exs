defmodule Edenflowers.ErrorTrackerIgnorerTest do
  use ExUnit.Case, async: true

  alias Edenflowers.ErrorTrackerIgnorer

  @not_found %ErrorTracker.Error{kind: "Elixir.Ash.Error.Query.NotFound"}

  test "ignores a request for a record that doesn't exist" do
    assert ErrorTrackerIgnorer.ignore?(@not_found, %{"request.path" => "/en/product/.env"})
  end

  test "tracks a missing record outside a request" do
    refute ErrorTrackerIgnorer.ignore?(@not_found, %{"job.worker" => "SomeWorker"})
  end

  test "tracks other errors in a request" do
    error = %ErrorTracker.Error{kind: "Elixir.RuntimeError"}
    refute ErrorTrackerIgnorer.ignore?(error, %{"request.path" => "/en/product/roses"})
  end
end

defmodule Edenflowers.ErrorTrackerIgnorer do
  @moduledoc """
  Keeps requests for records that don't exist out of ErrorTracker.

  Scanners probe paths like `/en/product/.env`, and each probe would otherwise
  be tracked as an error even though the visitor just gets a 404. A missing
  record outside a request, such as in an Oban job, is still tracked.
  """

  @behaviour ErrorTracker.Ignorer

  @impl true
  def ignore?(%ErrorTracker.Error{kind: kind}, context) do
    kind == to_string(Ash.Error.Query.NotFound) and Map.has_key?(context, "request.path")
  end
end

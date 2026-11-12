defmodule Edenflowers.WeatherStub do
  @moduledoc """
  Answers the weather request in tests: with the test's own `Req.Test` stub for
  `Edenflowers.External.WeatherAPI` when it has one, and otherwise as a forecast
  that is down.

  The Overview reads the weather in a background task that can outlive its test,
  and a `Req.Test` stub goes with the test process, so a stub set per test would
  leave that task with nothing to call.
  """

  @behaviour Plug

  alias Edenflowers.External.WeatherAPI

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Req.Test.call(conn, WeatherAPI)
  rescue
    # Req.Test raises this when the calling process has no stub.
    RuntimeError -> Plug.Conn.send_resp(conn, 503, "")
  end
end

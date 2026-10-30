defmodule EdenflowersWeb.Analytics do
  @moduledoc """
  Custom Umami events, sent from LiveViews.

  The event goes to the browser, which passes it to `umami.track`, so it keeps
  the visit's referrer and UTM campaign. Pages without the tracker (admin, staff,
  dev) drop it there.
  """

  import Phoenix.LiveView, only: [push_event: 3]

  @doc """
  Pushes event `name` with `data` to the browser.

  `once:` takes a key the browser remembers, so an event that marks a one-off
  (an order placed, a checkout started) isn't counted again on a reload or a
  revisit from the same browser.
  """
  def track(socket, name, data \\ %{}, opts \\ []) do
    push_event(socket, "umami", %{name: name, data: data, once: opts[:once]})
  end

  @doc "Revenue in the shape Umami's revenue reports read."
  def revenue(%Decimal{} = amount), do: %{revenue: Decimal.to_float(amount), currency: "EUR"}
end

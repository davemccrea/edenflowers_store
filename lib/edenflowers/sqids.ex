defmodule Edenflowers.Sqids do
  use Sqids

  @impl true
  def child_spec() do
    child_spec(
      min_length: 5,
      alphabet: "ABCDEFGHIJKLMNPQRSTUVWXYZ123456789"
    )
  end
end

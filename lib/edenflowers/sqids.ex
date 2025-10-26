defmodule Edenflowers.Sqids do
  use Sqids

  @impl true
  def child_spec() do
    child_spec(
      min_length: 5,
      alphabet: "ABCDEFGHIJKLMNPQRSTUVWXYZ123456789"
    )
  end

  @doc """
  Safely decodes a Sqids string, returning {:ok, list} or {:error, reason}.
  """
  def decode(string) do
    {:ok, decode!(string)}
  rescue
    e -> {:error, e}
  end
end

defmodule Edenflowers.Store.Order.Changes.GenerateOrderReference do
  use Ash.Resource.Change

  @alphabet "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(changeset, :order_reference, generate())
  end

  @doc "Generates a customer-friendly order reference using Crockford Base32."
  def generate do
    <<value::unsigned-30, _::2>> = :crypto.strong_rand_bytes(4)

    encoded =
      for shift <- 25..0//-5, into: "" do
        binary_part(@alphabet, Bitwise.band(Bitwise.bsr(value, shift), 31), 1)
      end

    "EF-" <> encoded
  end
end

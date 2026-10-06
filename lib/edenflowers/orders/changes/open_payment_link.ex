defmodule Edenflowers.Orders.Changes.OpenPaymentLink do
  @moduledoc "Gives the order a payment link, keeping the one it already has."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :payment_link_token) do
      changeset
    else
      Ash.Changeset.force_change_attribute(changeset, :payment_link_token, new_token())
    end
  end

  defp new_token, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end

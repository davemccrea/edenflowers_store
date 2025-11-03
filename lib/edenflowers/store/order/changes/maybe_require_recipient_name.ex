defmodule Edenflowers.Store.Order.MaybeRequireRecipientName do
  @moduledoc """
  Conditionally requires a recipient name for gift orders.

  If the order is marked as a gift (gift flag is true), this change
  ensures that a recipient_name is provided. For non-gift orders,
  the recipient name is optional.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_argument_or_attribute(changeset, :gift) do
      Ash.Changeset.require_values(changeset, :update, false, [:recipient_name])
    else
      changeset
    end
  end
end

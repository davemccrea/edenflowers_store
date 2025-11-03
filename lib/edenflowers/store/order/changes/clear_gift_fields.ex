defmodule Edenflowers.Store.Order.ClearGiftFields do
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      gift = Ash.Changeset.get_argument_or_attribute(changeset, :gift)

      if not gift do
        Ash.Changeset.force_change_attributes(changeset, %{
          recipient_name: nil,
          gift_message: nil
        })
      else
        changeset
      end
    end)
  end
end

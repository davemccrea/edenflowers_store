defmodule Edenflowers.Store.Order.Changes.TrimCardMessage do
  @moduledoc """
  Trims leading and trailing whitespace from card_message before validation.

  An all-whitespace value collapses to nil so length validation treats it
  the same as an unset message.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :card_message) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> Ash.Changeset.force_change_attribute(changeset, :card_message, nil)
          trimmed -> Ash.Changeset.force_change_attribute(changeset, :card_message, trimmed)
        end

      _ ->
        changeset
    end
  end
end

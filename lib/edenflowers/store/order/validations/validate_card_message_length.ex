defmodule Edenflowers.Store.Order.Validations.ValidateCardMessageLength do
  @moduledoc """
  Enforces the per-card-size length limit for card_message.

  Requires `line_items` to be loaded on the changeset's data; raises otherwise.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Store.ProductVariantSize

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :card_message) do
      nil ->
        :ok

      "" ->
        :ok

      message when is_binary(message) ->
        case card_line_item(changeset) do
          nil ->
            {:error, field: :card_message, message: ~t"Select a card before writing a message"}

          %{card_size: size} ->
            max = ProductVariantSize.max_message_length(size)

            if String.length(message) > max do
              {:error, field: :card_message, message: ~t"Must be at most #{max} characters"}
            else
              :ok
            end
        end
    end
  end

  defp card_line_item(changeset) do
    case changeset.data.line_items do
      %Ash.NotLoaded{} ->
        raise "ValidateCardMessageLength requires line_items to be loaded on the order"

      items when is_list(items) ->
        Enum.find(items, & &1.is_card)
    end
  end
end

defmodule Edenflowers.Orders.Validations.CardMessageLength do
  @moduledoc """
  Enforces the per-card-size length limit for card_message.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Catalog.ProductVariantSize

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :card_message) do
      nil ->
        :ok

      message ->
        case card_line_item(changeset) do
          nil ->
            {:error, field: :card_message, message: ~t"Select a card before writing a message"}

          %{variant_size: size} ->
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
    changeset.data
    |> Ash.load!(:line_items, lazy?: true, authorize?: false)
    |> Map.fetch!(:line_items)
    |> Enum.find(& &1.is_card)
  end
end

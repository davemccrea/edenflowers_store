defmodule Edenflowers.Orders.Validations.CardMessageLength do
  @moduledoc """
  Enforces the per-card-size length limit for card_message.

  An order Jennie enters or edits is held to the card she chose
  (`card_variant_id`). It needs no card: she may write a card or ribbon of her
  own, which is held to the longest card's limit.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Catalog
  alias Edenflowers.Catalog.ProductVariantSize

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :card_message) do
      nil ->
        :ok

      message ->
        if Ash.Changeset.get_attribute(changeset, :origin) == :custom or changeset.action.name == :edit do
          check_length(message, ProductVariantSize.max_message_length(chosen_card_size(changeset)))
        else
          validate_against_card(changeset, message)
        end
    end
  end

  defp validate_against_card(changeset, message) do
    case card_line_item(changeset) do
      nil ->
        {:error, field: :card_message, message: ~t"Select a card before writing a message"}

      %{variant_size: size} ->
        check_length(message, ProductVariantSize.max_message_length(size))
    end
  end

  defp check_length(message, max) do
    if String.length(message) > max do
      {:error, field: :card_message, message: ~t"Must be at most #{max} characters"}
    else
      :ok
    end
  end

  defp chosen_card_size(changeset) do
    with variant_id when not is_nil(variant_id) <- Ash.Changeset.get_argument(changeset, :card_variant_id),
         {:ok, %{size: size}} when not is_nil(size) <- Catalog.get_variant_by_id(variant_id, authorize?: false) do
      size
    else
      _ -> :large
    end
  end

  defp card_line_item(changeset) do
    changeset.data
    |> Ash.load!(:line_items, lazy?: true, authorize?: false)
    |> Map.fetch!(:line_items)
    |> Enum.find(& &1.is_card)
  end
end

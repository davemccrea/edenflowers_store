defmodule Edenflowers.Orders.LineItem.Validations.BowColour do
  @moduledoc """
  A line has a bow colour only when its product offers one, and the customer
  has to choose one.

  Customer checkout is held to the choice; a Custom Order line may leave it
  to Jennie.
  """

  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Catalog

  @impl true
  def validate(changeset, opts, _context) do
    variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)
    colour = Ash.Changeset.get_attribute(changeset, :bow_colour)

    with false <- is_nil(variant_id),
         {:ok, %{product: %{bow_colours: colours}}} <-
           Catalog.get_variant_by_id(variant_id, load: [product: [:bow_colours]], authorize?: false) do
      check(colour, colours, opts)
    else
      _ -> :ok
    end
  end

  defp check(nil, [], _opts), do: :ok

  defp check(nil, _colours, opts) do
    if opts[:required?], do: {:error, field: :bow_colour, message: ~t"choose a bow colour"}, else: :ok
  end

  defp check(colour, colours, _opts) do
    if colour in colours, do: :ok, else: {:error, field: :bow_colour, message: ~t"is not a colour it offers"}
  end
end

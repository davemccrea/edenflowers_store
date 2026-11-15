defmodule Edenflowers.Catalog.BowColour do
  @moduledoc """
  The bows a product can come with, chosen by the customer on its page. A
  product offers some of them; a line records the one chosen.
  """

  # Never remove a bow: past lines store it, and their orders would stop loading.
  use Ash.Type.Enum, values: [:red_satin, :jute]
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "shared"]

  def label(:red_satin), do: ~t"Red satin bow"
  def label(:jute), do: ~t"Jute bow"
end

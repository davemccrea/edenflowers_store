defmodule Edenflowers.Catalog.BowColour do
  @moduledoc """
  The colours of bow a product can come with, chosen by the customer on its
  page. A product offers some of them; a line records the one chosen.
  """

  # Never remove a colour: past lines store it, and their orders would stop loading.
  use Ash.Type.Enum, values: [:red, :yellow, :blue]
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "shared"]

  def label(:red), do: ~t"Red bow"
  def label(:yellow), do: ~t"Yellow bow"
  def label(:blue), do: ~t"Blue bow"
end

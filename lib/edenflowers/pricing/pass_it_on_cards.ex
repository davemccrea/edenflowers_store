defmodule Edenflowers.Pricing.PassItOnCards do
  @moduledoc """
  Renders a print shop's PDF of pass-it-on cards, one card per code from
  `Pricing.create_pass_it_on_batch/2`: two pages per card, with 3 mm bleed.
  The layout and wording live in `priv/receipts/pass-it-on.typ`.
  """

  alias Edenflowers.Typst

  # Printed on the cards, so it must outlive any change to the site's routes.
  @landing_url "https://edenflowers.fi/pass-it-on"

  def render(codes) when codes != [] do
    Typst.render("pass-it-on-main.typ", "cards", %{cards: Enum.map(codes, &%{code: &1, url: url(&1)})})
  end

  def url(code) do
    query = URI.encode_query(code: code, utm_source: "card", utm_medium: "print", utm_campaign: "pass-it-on")
    @landing_url <> "?" <> query
  end
end

defmodule EdenflowersWeb.CardDrawerTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EdenflowersWeb.CardDrawer

  defp card(name, size, price, position \\ nil, dimensions_cm \\ nil) do
    %{
      id: name,
      size: size,
      price: Decimal.new(price),
      dimensions_cm: dimensions_cm,
      photo_slug: "local:///cards/#{name}.png",
      product: %{name: name, position: position}
    }
  end

  defp render_drawer(variants) do
    render_component(&CardDrawer.card_drawer/1, variants: variants, locale: "en-GB")
  end

  test "groups Small, Medium, Large in order, positioned cards first, then by name" do
    html =
      render_drawer([
        card("Kira", :large, "4.90"),
        card("Poppies", :medium, "3.50"),
        card("Aruba", :large, "4.90"),
        card("Meadow", :large, "4.90", 0),
        card("Dahlias", :small, "1.90")
      ])

    positions = Enum.map(~w(Dahlias Poppies Meadow Aruba Kira), &(:binary.match(html, "card-option-#{&1}") |> elem(0)))

    assert positions == Enum.sort(positions)
  end

  test "a size whose cards share a price shows it once, in the heading" do
    html = render_drawer([card("Aruba", :large, "4.90"), card("Kira", :large, "4.90")])

    assert length(String.split(html, "€4.90")) == 2
  end

  test "a size with mixed prices shows each card's own price and none in the heading" do
    html = render_drawer([card("Aruba", :large, "4.90"), card("Kira", :large, "6.00")])

    assert length(String.split(html, "€4.90")) == 2
    assert length(String.split(html, "€6.00")) == 2
  end

  test "a size whose cards share dimensions shows them once, in the heading" do
    html = render_drawer([card("Aruba", :large, "4.90", nil, "10 × 15"), card("Kira", :large, "4.90", nil, "10 × 15")])

    assert length(String.split(html, "10 × 15 cm")) == 2
  end

  test "a size with mixed dimensions shows each card's own" do
    html =
      render_drawer([
        card("Aruba", :large, "4.90", nil, "10 × 15"),
        card("Kira", :large, "4.90", nil, "12 × 17")
      ])

    assert length(String.split(html, "10 × 15 cm")) == 2
    assert length(String.split(html, "12 × 17 cm")) == 2
  end
end

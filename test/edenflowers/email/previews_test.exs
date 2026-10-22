defmodule Edenflowers.Email.PreviewsTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Email
  alias Edenflowers.Email.Previews

  # The error alert and shop notice aren't sent to customers, so Jennie has nothing to proofread.
  @not_previewed [:error_alert, :shop_notice]

  test "every customer email has a preview" do
    builders = Email.__info__(:functions) |> Enum.map(fn {name, _arity} -> name end) |> MapSet.new()
    previewed = MapSet.new(Previews.all("en-GB"), fn {_email_type, _scenario, builder, _email} -> builder end)

    assert MapSet.difference(builders, previewed) == MapSet.new(@not_previewed)
  end

  test "renders in the requested language" do
    assert [{"Order confirmation", _scenario, :order_confirmation, email} | _] = Previews.all("fi")
    assert email.text_body =~ "lauantaina 14.11.2026"
  end

  test "a cancellation says the refund went back the way the customer paid" do
    bodies =
      for {"Order cancelled", scenario, _, email} <- Previews.all("en-GB"), into: %{}, do: {scenario, email.text_body}

    assert bodies["refunded to a card"] =~ "to your Visa card ending in 4242."
    assert bodies["refunded to MobilePay"] =~ "to your MobilePay."
    assert bodies["refunded, paid more than one way"] =~ "the way you paid."
  end
end

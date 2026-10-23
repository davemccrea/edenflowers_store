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
    assert [{"Order receipt", _scenario, :order_confirmation, email} | _] = Previews.all("fi")
    assert email.text_body =~ "lauantaina 14.11.2026"
  end

  test "a cancellation says the refund went back the way the customer paid" do
    bodies =
      for {"Order cancelled", scenario, _, email} <- Previews.all("en-GB"), into: %{}, do: {scenario, email.text_body}

    assert bodies["refunded to a card"] =~ "to your Visa card ending in 4242."
    assert bodies["refunded to MobilePay"] =~ "to your MobilePay."
    assert bodies["refunded, paid more than one way"] =~ "the way you paid."

    assert bodies["by the shop, with a reason, part paid in cash"] =~
             "I'll pay back the other €30.00 the same way you paid it."
  end

  test "Jennie's message comes after the line saying what happened, before the details" do
    [body] =
      for {"Order details", "with a message from Jennie", _, email} <- Previews.all("en-GB"), do: email.text_body

    assert body =~ ~r/Here is what we agreed:\n\nThe peonies are lovely this week, so I've added a few\.\n\n1 × /
  end

  test "the routine subscription charge is matter-of-fact, from the shop rather than Jennie" do
    [email | _] =
      for {"Subscription delivery charged", _, _, email} <- Previews.all("en-GB"), do: email

    assert email.from == {"Eden Flowers", elem(Application.fetch_env!(:edenflowers, :mailer_from_address), 1)}
    assert email.subject == "Your flowers for Saturday 14.11."
    assert email.text_body =~ ~r/^Your card was charged €59\.00 for your .+ delivery on Saturday 14\.11\.2026\./
    assert String.ends_with?(email.text_body, "\nEden Flowers\n")
  end
end

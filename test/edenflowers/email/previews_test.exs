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
    previews = Previews.all("fi")
    assert [{"Order receipt", _scenario, :order_confirmation, email} | _] = previews
    assert email.text_body =~ "lauantaina 14.11.2026"
    assert email.subject == "Eden Flowers -tilauksesi: lauantai 14.11."

    subjects = for {"Subscription heads-up", _, _, email} <- previews, do: email.subject

    assert subjects == [
             "Seuraavat kukkasi tulevat lauantaina 28.11.",
             "Seuraavat kukkasi ovat valmiina lauantaina 28.11."
           ]
  end

  test "a cancellation says the refund went back the way the customer paid" do
    bodies =
      for {"Cancellation confirmed", scenario, _, email} <- Previews.all("en-GB"),
          into: %{},
          do: {scenario, email.text_body}

    assert bodies["refunded to a card"] =~ "Refund: 64,00 € to Visa •••• 4242"
    assert bodies["refunded to MobilePay"] =~ "Refund: 64,00 € to MobilePay"
    assert bodies["refunded, paid more than one way"] =~ "Refund: 64,00 €, the way you paid"
  end

  test "a card refund says how long it takes; cash says it was handed back" do
    bodies =
      for {"Order refunded", scenario, _, email} <- Previews.all("en-GB"), into: %{}, do: {scenario, email.text_body}

    assert bodies["to a card through Stripe, with a message from Jennie"] =~
             ~r/ending in 4242\. It can take a few days to show on your statement\.\n\nI'm so sorry/

    assert bodies["handed back in cash"] =~ "I've refunded 20,00 € in cash."
    refute bodies["handed back in cash"] =~ "statement"
  end

  test "the routine subscription charge is matter-of-fact, from the shop rather than Jennie" do
    [email | _] =
      for {"Subscription delivery charged", _, _, email} <- Previews.all("en-GB"), do: email

    assert email.from == {"Eden Flowers", elem(Application.fetch_env!(:edenflowers, :mailer_from_address), 1)}
    assert email.subject == "Your flowers for Saturday 14.11."

    assert email.text_body =~
             ~r/^Your card was charged 59,00 € for your delivery scheduled for Saturday 14\.11\.2026 \(.+\)\./

    assert String.ends_with?(email.text_body, "\nEden Flowers\n")
  end
end

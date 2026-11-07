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

    subjects = for {"Subscription heads-up", _, _, email} <- previews, uniq: true, do: email.subject

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

    assert bodies["to a card through Stripe"] =~ "ending in 4242. It can take a few days to show on your statement."

    assert bodies["handed back in cash"] =~ "I've refunded 20,00 € in cash."
    refute bodies["handed back in cash"] =~ "statement"
    assert bodies["gift voucher sale handed back in cash"] =~ "I've refunded 20,00 € in cash."
  end

  test "a gift voucher refund names the voucher in each language without a fulfillment date" do
    for {locale, subject} <- [
          {"en-GB", "A refund for your Eden Flowers gift voucher"},
          {"sv-FI", "En återbetalning för ditt Eden Flowers-presentkort"},
          {"fi", "Hyvitys Eden Flowers -lahjakortistasi"}
        ] do
      [{_, _, _, email}] =
        Enum.filter(Previews.all(locale), fn {type, scenario, _, _} ->
          type == "Order refunded" and scenario == "gift voucher sale handed back in cash"
        end)

      assert email.subject == subject
      refute email.text_body =~ "%{"
    end
  end

  test "a cancellation promises an in-person refund, rather than claiming it already happened" do
    emails =
      for {"Order cancelled", scenario, _, email} <- Previews.all("en-GB"), into: %{}, do: {scenario, email}

    cash = emails["gift voucher sale paid in person, still to hand back"]
    assert cash.text_body =~ "Your gift voucher is cancelled."
    assert cash.text_body =~ "I'll pay back 50,00 € the same way you paid it."
    refute cash.text_body =~ "I've refunded"

    kept = emails["gift voucher sale paid in person, cancellation charge kept"]
    assert kept.text_body =~ "I've kept 5,00 € as a cancellation charge."
    assert kept.text_body =~ "I'll pay back 45,00 € the same way you paid it."
  end

  test "subscription receipts distinguish voucher payments from the card charge" do
    bodies =
      for {"Subscription delivery charged", scenario, _, email} <- Previews.all("en-GB"),
          into: %{},
          do: {scenario, email.text_body}

    assert bodies["delivery partly paid by gift voucher"] =~ "Your card was charged 39,00 €"
    assert bodies["delivery partly paid by gift voucher"] =~ "Paid with your gift voucher: 20,00 €."

    for scenario <- ["delivery fully paid by gift voucher", "pickup fully paid by gift voucher"] do
      assert bodies[scenario] =~ "Your gift voucher paid 59,00 €"
      refute bodies[scenario] =~ "Your card was charged"
    end

    assert bodies["nothing to charge"] =~ "Your receipt is attached."
    refute bodies["nothing to charge"] =~ "Your card was charged"
    refute bodies["nothing to charge"] =~ "Your gift voucher paid"
  end

  test "the subscription heads-up leaves Stripe's minimum charge when a voucher nearly pays it all" do
    [{_, _, _, email}] =
      Enum.filter(Previews.all("en-GB"), fn {type, scenario, _, _} ->
        type == "Subscription heads-up" and scenario == "gift voucher leaves the minimum card charge"
      end)

    assert email.text_body =~ "Your gift voucher pays 58,50 € of it"
    assert email.text_body =~ "your card will be charged the remaining 0,50 €"
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

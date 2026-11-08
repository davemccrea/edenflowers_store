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

  test "cancellation emails distinguish charges, balances still to pay and refunds still to return" do
    emails =
      for {"Order cancelled", scenario, _, email} <- Previews.all("en-GB"), into: %{}, do: {scenario, email}

    cash = emails["gift voucher sale paid in person, still to hand back"]
    assert cash.text_body =~ "Your gift voucher is cancelled."
    assert cash.text_body =~ "I'll pay back 50,00 € the same way you paid it."
    refute cash.text_body =~ "I've refunded"

    kept = emails["gift voucher sale paid in person, cancellation charge kept"]
    assert kept.text_body =~ "I've kept 5,00 € as a cancellation charge."
    assert kept.text_body =~ "I'll pay back 45,00 € the same way you paid it."
    refute kept.text_body =~ "I'll be in touch about how to pay it."

    mixed = emails["part paid by card, part in cash"]
    assert mixed.text_body =~ "I've refunded 34,00 €"
    assert mixed.text_body =~ "I'll pay back 30,00 € the same way you paid it."

    bookings =
      for {"Booking cancelled", scenario, _, email} <- Previews.all("en-GB"), into: %{}, do: {scenario, email}

    unpaid = bookings["unpaid by bank transfer, cancellation charge outstanding"]
    assert unpaid.text_body =~ "There's a cancellation charge of 22,50 €. I'll be in touch about how to pay it."

    partial = bookings["part paid, the rest of a cancellation charge still to pay"]

    assert partial.text_body =~
             "There's a cancellation charge of 22,50 €, and 12,50 € of it is still to pay. I'll be in touch about how to pay it."
  end

  test "subscription receipts use the same wording for delivery and pickup in each language" do
    for {locale, opening} <- [
          {"en-GB", "Thank you for your payment. Your receipt for the order on"},
          {"sv-FI", "Tack för din betalning. Kvittot för din beställning"},
          {"fi", "Kiitos maksustasi. Kuitti tilauksestasi"}
        ] do
      bodies =
        for {"Subscription delivery charged", scenario, _, email} <- Previews.all(locale),
            into: %{},
            do: {scenario, email.text_body}

      assert bodies["delivery"] == bodies["pickup"]
      assert bodies["delivery"] =~ opening
      assert bodies["delivery"] =~ "14.11.2026"
      assert bodies["pickup"] =~ "14.11.2026"
      refute bodies["delivery"] =~ "%{"
      refute bodies["pickup"] =~ "%{"
    end
  end

  test "the subscription heads-up gives the price and payment date, naming the gift voucher only when one pays towards it" do
    bodies =
      for {"Subscription heads-up", scenario, _, email} <- Previews.all("en-GB"),
          into: %{},
          do: {scenario, email.text_body}

    assert bodies["delivery"] =~ "Your card will be charged 59,00 € on Thursday 26.11.2026."
    assert bodies["pickup, every 4 weeks"] =~ "Your card will be charged 49,00 € on Thursday 26.11.2026."
    refute bodies["delivery"] =~ "gift voucher"

    assert bodies["gift voucher pays towards it"] =~
             "Your next flowers cost 59,00 €. On Thursday 26.11.2026, we'll apply your available gift voucher balance and charge any remaining amount to your card."

    for {_scenario, body} <- bodies, do: assert(body =~ "in your account by Wednesday 25.11.2026:")
  end

  test "the routine subscription charge is matter-of-fact, from the shop rather than Jennie" do
    [email | _] =
      for {"Subscription delivery charged", _, _, email} <- Previews.all("en-GB"), do: email

    assert email.from == {"Eden Flowers", elem(Application.fetch_env!(:edenflowers, :mailer_from_address), 1)}
    assert email.subject == "Your flowers for Saturday 14.11."

    assert email.text_body =~
             ~r/^Thank you for your payment\. Your receipt for the order on Saturday 14\.11\.2026 \(.+\) is attached\./

    assert String.ends_with?(email.text_body, "\nEden Flowers\n")
  end

  test "a gift recipient does not change notification wording in any language" do
    for locale <- ["en-GB", "sv-FI", "fi"], type <- ["Delivered", "Left at the door", "Gift voucher"] do
      variants =
        for {^type, scenario, _, email} <- Previews.all(locale),
            scenario not in ["no customer first name", "collecting a gift card at the shop"],
            uniq: true,
            do: {email.subject, email.text_body}

      assert length(variants) == 1
    end
  end

  test "email subjects and bodies contain no em dashes in any language" do
    for locale <- ["en-GB", "sv-FI", "fi"], {type, scenario, _, email} <- Previews.all(locale) do
      refute String.contains?(email.subject <> email.text_body, "\u2014"), "#{locale}: #{type}, #{scenario}"
    end
  end
end

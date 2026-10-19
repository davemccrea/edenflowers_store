defmodule Edenflowers.Email.Previews do
  @moduledoc """
  Every wording variant of every customer email, rendered by the real builders
  in `Edenflowers.Email` from fictional data, for the admin's Emails page.
  Building an email never sends it or touches the database.

  When a template gains or changes conditional copy, add or adjust a scenario
  here so Jennie can proofread it.
  """

  alias Edenflowers.Email

  @payment_link "https://buy.stripe.com/test_example"

  @doc """
  `{email_type, scenario, builder, email}` for every scenario, in `locale`,
  grouped by email type. Builders without a
  record to take the locale from use the caller's, as in production.
  """
  @spec all(String.t()) :: [{String.t(), String.t(), atom(), Swoosh.Email.t()}]
  def all(locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      order_confirmation(locale) ++
        order_details(locale) ++
        payment_failed(locale) ++
        subscription_set_up(locale) ++
        order_fulfilled(locale) ++
        order_left_at_door(locale) ++
        order_cancelled(locale) ++
        course_confirmation(locale) ++
        course_payment_link(locale) ++
        wedding_enquiry(locale) ++
        account_and_newsletter(locale)
    end)
  end

  defp order_confirmation(locale) do
    for {title, attrs} <- [
          {"not yet fulfilled, cancellable", %{}},
          {"not yet fulfilled, past the cancellation deadline", %{cancellable_by_customer?: false}},
          {"fulfilled at checkout (counter sale)", %{fulfillment_status: :fulfilled, cancellable_by_customer?: false}},
          {"with a delivery time", %{fulfillment_time_start: ~T[14:00:00]}},
          {"with a delivery time window", %{fulfillment_time_start: ~T[12:00:00], fulfillment_time_end: ~T[16:00:00]}},
          {"pickup", %{fulfillment_method: :pickup, recipient_name: nil, delivery_address: nil}},
          {"subscription order", %{origin: :subscription, cancellable_by_customer?: false}},
          {"no customer first name", %{customer_first_name: nil}}
        ] do
      {"Order confirmation", title, :order_confirmation, Email.order_confirmation(order(attrs, locale))}
    end
  end

  defp order_details(locale) do
    for {title, attrs, link} <- [
          {"first send, delivery to a recipient, unpaid, payment link", %{payment_terms: :payment_link}, @payment_link},
          {"re-sent after an edit", %{order_details_emailed_at: ~U[2026-11-10 09:00:00Z]}, @payment_link},
          {"online order edited after payment, part paid",
           %{origin: :online, amount_paid: Decimal.new("54.00"), balance: Decimal.new("10.00")}, @payment_link},
          {"pickup, no recipient, no delivery fee",
           %{fulfillment_method: :pickup, fulfillment_fee: nil, recipient_name: nil, delivery_address: nil},
           @payment_link},
          {"part paid, payment link", %{amount_paid: Decimal.new("20.00"), balance: Decimal.new("44.00")},
           @payment_link},
          {"unpaid, invoice after delivery", %{payment_terms: :invoice}, nil},
          {"unpaid, invoice after pickup",
           %{payment_terms: :invoice, fulfillment_method: :pickup, fulfillment_fee: nil, recipient_name: nil}, nil},
          {"unpaid, pays on delivery", %{payment_terms: :on_fulfillment}, nil},
          {"unpaid, pays at pickup",
           %{payment_terms: :on_fulfillment, fulfillment_method: :pickup, fulfillment_fee: nil, recipient_name: nil},
           nil},
          {"zero delivery fee, with delivery time window",
           %{
             fulfillment_fee: Decimal.new(0),
             grand_total: Decimal.new("54.00"),
             balance: Decimal.new("54.00"),
             fulfillment_time_start: ~T[12:00:00],
             fulfillment_time_end: ~T[16:00:00]
           }, @payment_link},
          {"no customer first name", %{customer_first_name: nil}, @payment_link}
        ] do
      {"Order details (custom order)", title, :order_details, Email.order_details(order(attrs, locale), link)}
    end
  end

  defp payment_failed(locale) do
    for {title, attrs} <- [
          {"delivery", %{}},
          {"pickup, no customer first name", %{fulfillment_method: :pickup, customer_first_name: nil}}
        ] do
      {"Subscription payment failed", title, :payment_failed, Email.payment_failed(order(attrs, locale), @payment_link)}
    end
  end

  defp subscription_set_up(locale) do
    for {title, attrs} <- [
          {"delivery, every 2 weeks, discounted first order, card message", %{}},
          {"pickup, every week, no discount, no card message, no first name",
           %{
             fulfillment_option: %{fulfillment_method: :pickup},
             delivery_address: nil,
             interval_weeks: 1,
             next_fulfillment_date: ~D[2026-11-21],
             product_variant: %{size: :small, price: Decimal.new("35.00")},
             first_order_fulfillment_fee: Decimal.new(0),
             first_order_discounted?: false,
             card_message: nil,
             user: %{email: "maria@example.com", first_name: nil}
           }},
          {"delivery, every 4 weeks, large",
           %{
             interval_weeks: 4,
             next_fulfillment_date: ~D[2026-12-12],
             product_variant: %{size: :large, price: Decimal.new("69.00")}
           }}
        ] do
      {"Subscription set up", title, :subscription_set_up, Email.subscription_set_up(subscription(attrs, locale))}
    end
  end

  defp order_fulfilled(locale) do
    for {title, attrs} <-
          fulfillment_variants() ++
            [{"pickup", %{fulfillment_method: :pickup, gift: false, recipient_first_name: nil}}] do
      {"Order fulfilled", title, :order_fulfilled, Email.order_fulfilled(order(attrs, locale))}
    end
  end

  defp order_left_at_door(locale) do
    for {title, attrs} <- fulfillment_variants() do
      {"Order left at door (photo)", title, :order_left_at_door,
       Email.order_left_at_door(order(attrs, locale), "fictional-jpeg-bytes")}
    end
  end

  defp fulfillment_variants do
    [
      {"gift to a named recipient", %{}},
      {"gift without a recipient name", %{recipient_first_name: nil}},
      {"not a gift, recipient name filled in", %{gift: false}},
      {"no customer first name", %{customer_first_name: nil}}
    ]
  end

  defp order_cancelled(locale) do
    mobilepay = [%{amount: Decimal.new("64.00"), payment_method_type: "mobilepay", card_brand: nil, card_last4: nil}]

    [
      {"Order cancelled", "refunded to a card", :order_cancelled,
       Email.order_cancelled(order(%{}, locale), Decimal.new("64.00"))},
      {"Order cancelled", "refunded to MobilePay", :order_cancelled,
       Email.order_cancelled(order(%{payments: mobilepay}, locale), Decimal.new("64.00"))},
      {"Order cancelled", "refunded, paid more than one way", :order_cancelled,
       Email.order_cancelled(
         order(%{payments: [hd(order(%{}, locale).payments) | mobilepay]}, locale),
         Decimal.new("64.00")
       )},
      {"Order cancelled", "nothing to refund, no customer first name", :order_cancelled,
       Email.order_cancelled(order(%{customer_first_name: nil, payments: []}, locale), Decimal.new(0))}
    ]
  end

  defp course_confirmation(locale) do
    for {title, attrs, link} <- [
          {"unpaid, payment link", %{}, @payment_link},
          {"unpaid, pays at the course", %{}, nil},
          {"paid, late-cancellation fee", %{balance: Decimal.new(0)}, nil},
          {"paid, no late-cancellation fee",
           %{balance: Decimal.new(0), course: %{late_cancellation_fee: Decimal.new(0)}}, nil},
          {"2 places, paid", %{seats: 2, balance: Decimal.new(0)}, nil},
          {"2 places, unpaid, payment link", %{seats: 2, balance: Decimal.new("90.00")}, @payment_link},
          {"no first name", %{first_name: nil}, @payment_link}
        ] do
      {"Course confirmation", title, :course_confirmation, Email.course_confirmation(registration(attrs, locale), link)}
    end
  end

  defp course_payment_link(locale) do
    for {title, attrs} <- [{"named", %{}}, {"no first name", %{first_name: nil}}] do
      {"Course payment link", title, :course_payment_link,
       Email.course_payment_link(registration(attrs, locale), @payment_link)}
    end
  end

  defp wedding_enquiry(locale) do
    full = %{
      "name" => "Emma Lindqvist",
      "email" => "emma@example.com",
      "locale" => locale,
      "wedding_date" => ~D[2027-06-19],
      "venue" => "Villa Sjöhem",
      "guests" => 80,
      "selection" => ["Bridal bouquet", "2 × Bridesmaid bouquet", "8 × Table arrangement"],
      "estimate" => "€1,240.00",
      "message" => "We'd love something soft and white with a little green."
    }

    minimal = Map.merge(full, %{"venue" => nil, "guests" => nil, "selection" => [], "message" => nil})

    [
      {"Wedding enquiry copy", "everything filled in", :wedding_enquiry, Email.wedding_enquiry(full)},
      {"Wedding enquiry copy", "only the required fields", :wedding_enquiry, Email.wedding_enquiry(minimal)}
    ]
  end

  defp account_and_newsletter(locale) do
    promo = %{code: "WELCOME-7K2P", expiration_date: ~D[2026-11-18]}

    [
      {"Newsletter", "welcome with promo code", :newsletter_promo,
       Email.newsletter_promo("maria@example.com", promo, locale)},
      {"Newsletter", "already subscribed", :newsletter_already_subscribed,
       Email.newsletter_already_subscribed("maria@example.com", promo, locale)},
      {"Newsletter", "resubscribed", :newsletter_resubscribed, Email.newsletter_resubscribed("maria@example.com")},
      {"Account", "sign-in code", :otp_sign_in, Email.otp_sign_in("maria@example.com", "482913")},
      {"Account", "email change code", :email_change_code, Email.email_change_code("maria@example.com", "730184")}
    ]
  end

  defp order(attrs, locale) do
    Map.merge(
      %{
        order_reference: "EF-1042",
        locale: locale,
        customer_email: "maria@example.com",
        customer_first_name: "Maria",
        origin: :custom,
        payment_terms: nil,
        gift: true,
        recipient_name: "Sara Nyström",
        recipient_first_name: "Sara",
        fulfillment_method: :delivery,
        fulfillment_status: :pending,
        fulfillment_date: ~D[2026-11-14],
        fulfillment_time_start: nil,
        fulfillment_time_end: nil,
        delivery_address: "Strandgatan 12, 65100 Vaasa",
        cancellable_by_customer?: true,
        cancellable_until: ~D[2026-11-12],
        order_details_emailed_at: nil,
        line_items: [
          %{quantity: 1, product_name: "Seasonal bouquet, medium", subtotal: Decimal.new("49.00")},
          %{quantity: 1, product_name: "Vase", subtotal: Decimal.new("5.00")}
        ],
        fulfillment_fee: Decimal.new("10.00"),
        grand_total: Decimal.new("64.00"),
        amount_paid: Decimal.new(0),
        balance: Decimal.new("64.00"),
        payments: [%{amount: Decimal.new("64.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}]
      },
      attrs
    )
  end

  defp subscription(attrs, locale) do
    Map.merge(
      %{
        locale: locale,
        user: %{email: "maria@example.com", first_name: "Maria"},
        fulfillment_option: %{fulfillment_method: :delivery},
        product_variant: %{size: :medium, price: Decimal.new("49.00")},
        first_order_fulfillment_fee: Decimal.new("10.00"),
        interval_weeks: 2,
        delivery_address: "Strandgatan 12, 65100 Vaasa",
        first_delivery_date: ~D[2026-11-14],
        next_fulfillment_date: ~D[2026-11-28],
        first_order_discounted?: true,
        card_message: "Happy birthday!"
      },
      attrs
    )
  end

  defp registration(attrs, locale) do
    course =
      Map.merge(
        %{
          name: "Autumn Wreaths",
          date: ~D[2026-11-20],
          start_time: ~T[18:00:00],
          end_time: ~T[20:00:00],
          location_name: "Eden Flowers studio",
          location_address: "Storgatan 1, 65100 Vaasa",
          late_cancellation_fee: Decimal.new("15.00")
        },
        Map.get(attrs, :course, %{})
      )

    %{
      first_name: "Anna",
      email: "anna@example.com",
      locale: locale,
      seats: 1,
      balance: Decimal.new("45.00")
    }
    |> Map.merge(Map.delete(attrs, :course))
    |> Map.put(:course, course)
  end
end

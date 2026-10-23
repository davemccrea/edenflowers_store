defmodule Edenflowers.Email.Previews do
  @moduledoc """
  Every wording variant of every customer email, rendered by the real builders
  in `Edenflowers.Email` from fictional data, for the admin's Emails page.
  Building an email never sends it or touches the database.

  When a template gains or changes conditional copy, add or adjust a scenario
  here so Jennie can proofread it.
  """

  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Orders.Order

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
        subscription_set_up(locale) ++
        order_delivered(locale) ++
        order_cancelled(locale) ++
        order_refunded(locale) ++
        course_confirmation(locale) ++
        course_payment_link(locale) ++
        booking_cancelled(locale) ++
        booking_refunded(locale) ++
        wedding_enquiry(locale) ++
        account_and_newsletter(locale)
    end)
  end

  defp order_confirmation(locale) do
    for {title, attrs} <- [
          {gettext_noop("not yet fulfilled, cancellable"), %{}},
          {gettext_noop("not yet fulfilled, past the cancellation deadline"), %{cancellable_by_customer?: false}},
          {gettext_noop("fulfilled at checkout (counter sale)"),
           %{fulfillment_status: :fulfilled, cancellable_by_customer?: false}},
          {gettext_noop("with a delivery time"), %{fulfillment_time_start: ~T[14:00:00]}},
          {gettext_noop("with a delivery time window"),
           %{fulfillment_time_start: ~T[12:00:00], fulfillment_time_end: ~T[16:00:00]}},
          {gettext_noop("pickup"),
           %{
             fulfillment_method: :pickup,
             fulfillment_fee: nil,
             grand_total: Decimal.new("54.00"),
             amount_paid: Decimal.new("54.00"),
             balance: Decimal.new(0),
             payments: [
               %{amount: Decimal.new("54.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}
             ],
             recipient_name: nil,
             delivery_address: nil
           }},
          {gettext_noop("subscription order"), %{origin: :subscription, cancellable_by_customer?: false}},
          {gettext_noop("no customer first name"), %{customer_first_name: nil}}
        ] do
      paid_attrs = %{
        amount_paid: Decimal.new("64.00"),
        balance: Decimal.new(0),
        payments: [%{amount: Decimal.new("64.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}]
      }

      {gettext_noop("Order confirmation"), title, :order_confirmation,
       Email.order_confirmation(order(Map.merge(paid_attrs, attrs), locale))}
    end
  end

  defp order_details(locale) do
    for {title, attrs, link} <- [
          {gettext_noop("first send, delivery to a recipient, unpaid, payment link"), %{payment_terms: :payment_link},
           @payment_link},
          {gettext_noop("re-sent after an edit"), %{order_details_emailed_at: ~U[2026-11-10 09:00:00Z]}, @payment_link},
          {gettext_noop("online order edited after payment, part paid"),
           %{
             origin: :online,
             amount_paid: Decimal.new("54.00"),
             balance: Decimal.new("10.00"),
             payments: [
               %{amount: Decimal.new("54.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}
             ]
           }, @payment_link},
          {gettext_noop("pickup, no recipient, no delivery fee"),
           %{
             fulfillment_method: :pickup,
             fulfillment_fee: nil,
             grand_total: Decimal.new("54.00"),
             balance: Decimal.new("54.00"),
             recipient_name: nil,
             delivery_address: nil
           }, @payment_link},
          {gettext_noop("part paid, payment link"),
           %{
             amount_paid: Decimal.new("20.00"),
             balance: Decimal.new("44.00"),
             payments: [
               %{amount: Decimal.new("20.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}
             ]
           }, @payment_link},
          {gettext_noop("unpaid, invoice after delivery"), %{payment_terms: :invoice}, nil},
          {gettext_noop("unpaid, invoice after pickup"),
           %{
             payment_terms: :invoice,
             fulfillment_method: :pickup,
             fulfillment_fee: nil,
             grand_total: Decimal.new("54.00"),
             balance: Decimal.new("54.00"),
             recipient_name: nil
           }, nil},
          {gettext_noop("delivered, payment link"), %{fulfillment_status: :fulfilled}, @payment_link},
          {gettext_noop("unpaid, pays on delivery"), %{payment_terms: :on_fulfillment}, nil},
          {gettext_noop("unpaid, pays at pickup"),
           %{
             payment_terms: :on_fulfillment,
             fulfillment_method: :pickup,
             fulfillment_fee: nil,
             grand_total: Decimal.new("54.00"),
             balance: Decimal.new("54.00"),
             recipient_name: nil
           }, nil},
          {gettext_noop("zero delivery fee, with delivery time window"),
           %{
             fulfillment_fee: Decimal.new(0),
             grand_total: Decimal.new("54.00"),
             balance: Decimal.new("54.00"),
             fulfillment_time_start: ~T[12:00:00],
             fulfillment_time_end: ~T[16:00:00]
           }, @payment_link},
          {gettext_noop("settled, paid in full"),
           %{
             amount_paid: Decimal.new("64.00"),
             balance: Decimal.new(0),
             payments: [
               %{amount: Decimal.new("64.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}
             ]
           }, nil},
          {gettext_noop("overpaid, credit balance"),
           %{
             amount_paid: Decimal.new("70.00"),
             balance: Decimal.new("-6.00"),
             payments: [
               %{amount: Decimal.new("70.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}
             ]
           }, nil},
          {gettext_noop("no customer first name"), %{customer_first_name: nil}, @payment_link},
          {gettext_noop("subscription card refused, delivery"), card_refused(), @payment_link},
          {gettext_noop("subscription card refused, pickup, no customer first name"),
           Map.merge(card_refused(), %{
             fulfillment_method: :pickup,
             fulfillment_fee: nil,
             grand_total: Decimal.new("54.00"),
             balance: Decimal.new("54.00"),
             recipient_name: nil,
             delivery_address: nil,
             customer_first_name: nil
           }), @payment_link}
        ] do
      {gettext_noop("Order details"), title, :order_details, Email.order_details(order(attrs, locale), link)}
    end ++
      [
        {gettext_noop("Order details"), gettext_noop("with a message from Jennie"), :order_details,
         Email.order_details(order(%{}, locale), @payment_link, message(locale))}
      ]
  end

  defp card_refused, do: %{origin: :subscription, gift: false, recipient_name: nil, recipient_first_name: nil}

  defp subscription_set_up(locale) do
    for {title, attrs} <- [
          {gettext_noop("delivery, every 2 weeks, discounted first order, card message"), %{}},
          {gettext_noop("pickup, every week, no discount, no card message, no first name"),
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
          {gettext_noop("delivery, every 4 weeks, large"),
           %{
             interval_weeks: 4,
             next_fulfillment_date: ~D[2026-12-12],
             product_variant: %{size: :large, price: Decimal.new("69.00")}
           }},
          {gettext_noop("delivery, discount only"), %{first_order_discounted?: true, card_message: nil}},
          {gettext_noop("delivery, card message only"),
           %{first_order_discounted?: false, card_message: "Thinking of you!"}}
        ] do
      {gettext_noop("Subscription set up"), title, :subscription_set_up,
       Email.subscription_set_up(subscription(attrs, locale))}
    end
  end

  defp order_delivered(locale) do
    for {title, attrs, photo} <- [
          {gettext_noop("gift to a named recipient"), %{}, nil},
          {gettext_noop("gift without a recipient name"), %{recipient_first_name: nil}, nil},
          {gettext_noop("not a gift, recipient name filled in"), %{gift: false}, nil},
          {gettext_noop("no customer first name"), %{customer_first_name: nil}, nil},
          {gettext_noop("left at the door, gift to a named recipient"), %{}, "fictional-jpeg-bytes"},
          {gettext_noop("left at the door, not a gift"), %{gift: false}, "fictional-jpeg-bytes"}
        ] do
      {gettext_noop("Order delivered"), title, :order_delivered, Email.order_delivered(order(attrs, locale), photo)}
    end ++
      [
        {gettext_noop("Order delivered"), gettext_noop("with a message from Jennie"), :order_delivered,
         Email.order_delivered(order(%{}, locale), nil, message(locale))}
      ]
  end

  defp order_cancelled(locale) do
    mobilepay = [
      %{
        amount: Decimal.new("64.00"),
        method: :stripe,
        payment_method_type: "mobilepay",
        card_brand: nil,
        card_last4: nil
      }
    ]

    card = %{
      amount: Decimal.new("64.00"),
      method: :stripe,
      payment_method_type: "card",
      card_brand: "visa",
      card_last4: "4242"
    }

    cash = %{amount: Decimal.new("30.00"), method: :cash, payment_method_type: nil, card_brand: nil, card_last4: nil}
    paid_attrs = %{amount_paid: Decimal.new("64.00"), balance: Decimal.new(0)}
    refunded = fn amount -> %{refunded: Decimal.new(amount), to_return: Decimal.new(0)} end

    [
      {gettext_noop("Order cancelled"), gettext_noop("refunded to a card"), :cancelled,
       Email.cancelled(order(Map.merge(paid_attrs, %{payments: [card]}), locale), refunded.("64.00"), :customer)},
      {gettext_noop("Order cancelled"), gettext_noop("refunded to MobilePay"), :cancelled,
       Email.cancelled(
         order(Map.merge(paid_attrs, %{payments: mobilepay}), locale),
         refunded.("64.00"),
         :customer
       )},
      {gettext_noop("Order cancelled"), gettext_noop("refunded, paid more than one way"), :cancelled,
       Email.cancelled(
         order(
           Map.merge(
             paid_attrs,
             %{payments: [%{card | amount: Decimal.new("34.00")} | [%{hd(mobilepay) | amount: Decimal.new("30.00")}]]}
           ),
           locale
         ),
         refunded.("64.00"),
         :customer
       )},
      {gettext_noop("Order cancelled"), gettext_noop("pickup, refunded"), :cancelled,
       Email.cancelled(
         order(
           %{
             fulfillment_method: :pickup,
             fulfillment_fee: nil,
             grand_total: Decimal.new("54.00"),
             amount_paid: Decimal.new("54.00"),
             balance: Decimal.new(0),
             payments: [%{card | amount: Decimal.new("54.00")}],
             fulfillment_date: ~D[2026-11-14]
           },
           locale
         ),
         refunded.("54.00"),
         :customer
       )},
      {gettext_noop("Order cancelled"), gettext_noop("by the shop, with a reason, part paid in cash"), :cancelled,
       Email.cancelled(
         order(
           Map.merge(paid_attrs, %{
             payments: [%{card | amount: Decimal.new("34.00")}, cash],
             cancellation_reason: reason(locale)
           }),
           locale
         ),
         %{refunded: Decimal.new("34.00"), to_return: Decimal.new("30.00")},
         :shop
       )},
      {gettext_noop("Order cancelled"), gettext_noop("nothing to refund, no customer first name"), :cancelled,
       Email.cancelled(order(%{customer_first_name: nil, payments: []}, locale), refunded.("0"), :customer)}
    ]
  end

  defp course_confirmation(locale) do
    for {title, attrs} <- [
          {gettext_noop("paid"), %{balance: Decimal.new(0), amount_paid: Decimal.new("45.00")}},
          {gettext_noop("2 places, paid"), %{seats: 2, balance: Decimal.new(0), amount_paid: Decimal.new("90.00")}},
          {gettext_noop("no first name"),
           %{first_name: nil, balance: Decimal.new(0), amount_paid: Decimal.new("45.00")}},
          {gettext_noop("paid after the course"),
           %{balance: Decimal.new(0), amount_paid: Decimal.new("45.00"), course: %{date: ~D[2020-11-20]}}}
        ] do
      {gettext_noop("Course confirmation"), title, :course_confirmation,
       Email.course_confirmation(registration(attrs, locale))}
    end
  end

  defp course_payment_link(locale) do
    for {title, attrs} <- [
          {gettext_noop("awaiting payment"), %{status: :awaiting_payment}},
          {gettext_noop("2 places, awaiting payment"),
           %{status: :awaiting_payment, seats: 2, balance: Decimal.new("90.00")}},
          {gettext_noop("after the course"), %{status: :awaiting_payment, course: %{date: ~D[2020-11-20]}}},
          {gettext_noop("no first name"), %{status: :awaiting_payment, first_name: nil}}
        ] do
      {gettext_noop("Course payment link"), title, :course_payment_link,
       Email.course_payment_link(registration(attrs, locale), @payment_link)}
    end
  end

  defp order_refunded(locale) do
    card = %{
      amount: Decimal.new("64.00"),
      method: :stripe,
      payment_method_type: "card",
      card_brand: "visa",
      card_last4: "4242"
    }

    for {title, attrs, refund} <- [
          {gettext_noop("to a card, with a reason"), %{payments: [card]},
           %{amount: Decimal.new("20.00"), payment_method: :stripe, note: reason(locale)}},
          {gettext_noop("handed back in cash"), %{payments: []},
           %{amount: Decimal.new("20.00"), payment_method: :cash, note: nil}}
        ] do
      {gettext_noop("Order refunded"), title, :refunded, Email.refunded(order(attrs, locale), refund)}
    end
  end

  defp booking_refunded(locale) do
    refund = %{amount: Decimal.new("45.00"), payment_method: :cash, note: nil}

    [
      {gettext_noop("Booking refunded"), gettext_noop("handed back in cash"), :refunded,
       Email.refunded(registration(%{payments: []}, locale), refund)}
    ]
  end

  defp booking_cancelled(locale) do
    card = %{
      amount: Decimal.new("45.00"),
      method: :stripe,
      payment_method_type: "card",
      card_brand: "visa",
      card_last4: "4242"
    }

    cash = %{amount: Decimal.new("45.00"), method: :cash, payment_method_type: nil, card_brand: nil, card_last4: nil}

    for {title, attrs, money} <- [
          {gettext_noop("refunded to a card"), %{payments: [card]},
           %{refunded: Decimal.new("45.00"), to_return: Decimal.new(0)}},
          {gettext_noop("with a reason, paid in cash"), %{payments: [cash], cancellation_reason: reason(locale)},
           %{refunded: Decimal.new(0), to_return: Decimal.new("45.00")}},
          {gettext_noop("nothing paid, no first name"), %{first_name: nil, payments: []},
           %{refunded: Decimal.new(0), to_return: Decimal.new(0)}}
        ] do
      {gettext_noop("Booking cancelled"), title, :cancelled, Email.cancelled(registration(attrs, locale), money, :shop)}
    end
  end

  defp wedding_enquiry(locale) do
    {selection, message} =
      cond do
        String.starts_with?(locale, "fi") ->
          {["Morsiuskimppu", "2 × Kaasokimppu", "8 × Pöytäkoriste"], "Haluaisimme pehmeän valkoista ja hieman vihreää."}

        String.starts_with?(locale, "sv") ->
          {["Brudbukett", "2 × Tärnbukett", "8 × Bordsdekoration"], "Vi önskar något mjukt och vitt med lite grönt."}

        true ->
          {["Bridal bouquet", "2 × Bridesmaid bouquet", "8 × Table arrangement"],
           "We'd love something soft and white with a little green."}
      end

    full = %{
      "name" => "Emma Lindqvist",
      "email" => "emma@example.com",
      "locale" => locale,
      "wedding_date" => ~D[2027-06-19],
      "venue" => "Villa Sjöhem",
      "guests" => 80,
      "selection" => selection,
      "estimate" => "€1,240.00",
      "message" => message
    }

    minimal = Map.merge(full, %{"venue" => nil, "guests" => nil, "selection" => [], "message" => nil})

    [
      {gettext_noop("Wedding enquiry copy"), gettext_noop("everything filled in"), :wedding_enquiry,
       Email.wedding_enquiry(full)},
      {gettext_noop("Wedding enquiry copy"), gettext_noop("only the required fields"), :wedding_enquiry,
       Email.wedding_enquiry(minimal)}
    ]
  end

  defp account_and_newsletter(locale) do
    promo = %{code: "WELCOME-7K2P", expiration_date: ~D[2026-11-18]}

    [
      {gettext_noop("Newsletter"), gettext_noop("welcome with promo code"), :newsletter,
       Email.newsletter("maria@example.com", :new, promo, locale)},
      {gettext_noop("Newsletter"), gettext_noop("already subscribed"), :newsletter,
       Email.newsletter("maria@example.com", :again_with_code, promo, locale)},
      {gettext_noop("Newsletter"), gettext_noop("resubscribed, code used or expired"), :newsletter,
       Email.newsletter("maria@example.com", :again, nil, locale)},
      {gettext_noop("Account"), gettext_noop("sign-in code"), :otp_sign_in,
       Email.otp_sign_in("maria@example.com", "482913")},
      {gettext_noop("Account"), gettext_noop("email change code"), :email_change_code,
       Email.email_change_code("maria@example.com", "730184")}
    ]
  end

  # Jennie writes the reason herself, in the customer's language.
  defp reason(locale) do
    cond do
      String.starts_with?(locale, "fi") -> "Olen pahoillani, mutta olen sairaana sinä päivänä."
      String.starts_with?(locale, "sv") -> "Jag är ledsen, men jag är sjuk den dagen."
      true -> "I'm so sorry, but I'm ill that day."
    end
  end

  defp message(locale) do
    cond do
      String.starts_with?(locale, "fi") -> "Pionit ovat ihania tällä viikolla, joten lisäsin muutaman."
      String.starts_with?(locale, "sv") -> "Pionerna är så fina den här veckan, så jag lade till några."
      true -> "The peonies are lovely this week, so I've added a few."
    end
  end

  defp order(attrs, locale) do
    {bouquet, vase} =
      cond do
        String.starts_with?(locale, "fi") -> {"Sesongin kimppu, keskikokoinen", "Maljakko"}
        String.starts_with?(locale, "sv") -> {"Säsongsbukett, mellan", "Vas"}
        true -> {"Seasonal bouquet, medium", "Vase"}
      end

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
        cancellable_until: ~D[2026-11-09],
        cancellation_reason: nil,
        order_details_emailed_at: nil,
        line_items: [
          %{quantity: 1, product_name: bouquet, subtotal: Decimal.new("49.00")},
          %{quantity: 1, product_name: vase, subtotal: Decimal.new("5.00")}
        ],
        fulfillment_fee: Decimal.new("10.00"),
        grand_total: Decimal.new("64.00"),
        amount_paid: Decimal.new(0),
        balance: Decimal.new("64.00"),
        payments: []
      },
      attrs
    )
    # A struct, as Email picks an order's or a booking's template by it.
    |> then(&Map.merge(%Order{}, &1))
  end

  defp subscription(attrs, locale) do
    product_name =
      cond do
        String.starts_with?(locale, "fi") -> "Floristin valinta"
        String.starts_with?(locale, "sv") -> "Floristens val"
        true -> "Florist's choice bouquet"
      end

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
    |> put_in([:product_variant, :product], %{name: product_name})
  end

  defp registration(attrs, locale) do
    course_name =
      cond do
        String.starts_with?(locale, "fi") -> "Syksyiset kranssit"
        String.starts_with?(locale, "sv") -> "Höstkransar"
        true -> "Autumn Wreaths"
      end

    course =
      Map.merge(
        %{
          name: course_name,
          date: ~D[2026-11-20],
          start_time: ~T[18:00:00],
          end_time: ~T[20:00:00],
          location_name: "Eden Flowers studio",
          location_address: "Storgatan 1, 65100 Vaasa"
        },
        Map.get(attrs, :course, %{})
      )

    %{
      first_name: "Anna",
      email: "anna@example.com",
      locale: locale,
      seats: 1,
      balance: Decimal.new("45.00"),
      amount_paid: Decimal.new(0),
      cancellation_reason: nil
    }
    |> Map.merge(Map.delete(attrs, :course))
    |> Map.put(:course, course)
    |> then(&Map.merge(%CourseRegistration{}, &1))
  end
end

defmodule Edenflowers.Email.Previews do
  @moduledoc """
  Every wording variant of every customer email, rendered by the real builders
  in `Edenflowers.Email` from fictional data, so an agent can review the copy
  and its translations with `mix print_emails`. Building an email never sends
  it or touches the database.

  When a template gains or changes conditional copy, add or adjust a scenario
  here. Email types and scenarios are English labels for the reviewer.
  """

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
        order_updated(locale) ++
        payment_received(locale) ++
        payment_reminder(locale) ++
        purchase_receipt(locale) ++
        subscription_payment_failed(locale) ++
        subscription_charged(locale) ++
        subscription_set_up(locale) ++
        subscription_cancelled(locale) ++
        subscription_cancellation_confirmed(locale) ++
        subscription_heads_up(locale) ++
        order_delivered(locale) ++
        order_left_at_door(locale) ++
        order_cancelled(locale) ++
        cancellation_confirmed(locale) ++
        order_refunded(locale) ++
        course_confirmation(locale) ++
        course_payment_link(locale) ++
        course_reminder(locale) ++
        booking_cancelled(locale) ++
        booking_refunded(locale) ++
        wedding_enquiry(locale) ++
        account_and_newsletter(locale)
    end)
  end

  defp order_confirmation(locale) do
    for {title, attrs} <- [
          {"not yet fulfilled, cancellable", %{}},
          {"not yet fulfilled, past the cancellation deadline", %{cancellable_by_customer?: false}},
          {"gift with a card message, promo code",
           %{
             card_message: card_message(locale),
             discount: Decimal.new("4.90"),
             grand_total: Decimal.new("59.10"),
             amount_paid: Decimal.new("59.10")
           }},
          {"with a delivery time", %{fulfillment_time_start: ~T[14:00:00]}},
          {"with a delivery time window", %{fulfillment_time_start: ~T[12:00:00], fulfillment_time_end: ~T[16:00:00]}},
          {"pickup",
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
          {"no customer first name", %{customer_first_name: nil}}
        ] do
      paid_attrs = %{
        amount_paid: Decimal.new("64.00"),
        balance: Decimal.new(0),
        payments: [%{amount: Decimal.new("64.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}]
      }

      {"Order receipt", title, :order_confirmation,
       Email.order_confirmation(order(Map.merge(paid_attrs, attrs), locale))}
    end
  end

  defp order_details(locale) do
    for {title, attrs, link} <- [
          {"gift with a card message, delivery, payment link",
           %{payment_terms: :payment_link, card_message: card_message(locale)}, @payment_link},
          {"pickup, no recipient, no delivery fee", pickup(), @payment_link},
          {"part paid, payment link", part_paid(), @payment_link},
          {"unpaid, invoice after delivery", %{payment_terms: :invoice}, nil},
          {"unpaid, invoice after pickup", Map.put(pickup(), :payment_terms, :invoice), nil},
          {"unpaid, pays on delivery", %{payment_terms: :on_fulfillment}, nil},
          {"unpaid, pays at pickup", Map.put(pickup(), :payment_terms, :on_fulfillment), nil},
          {"zero delivery fee, with delivery time window",
           %{
             fulfillment_fee: Decimal.new(0),
             grand_total: Decimal.new("54.00"),
             balance: Decimal.new("54.00"),
             fulfillment_time_start: ~T[12:00:00],
             fulfillment_time_end: ~T[16:00:00]
           }, @payment_link},
          {"settled, paid in full", paid_in_full(), nil},
          {"sent after it was handed over, invoice", %{fulfillment_status: :fulfilled, payment_terms: :invoice}, nil},
          {"no customer first name", %{customer_first_name: nil}, @payment_link}
        ] do
      {"Order details", title, :order_details, Email.order_details(order(attrs, locale), link)}
    end ++
      [
        {"Order details", "with a message from Jennie", :order_details,
         Email.order_details(order(%{}, locale), @payment_link, message(locale))}
      ]
  end

  defp order_updated(locale) do
    for {title, attrs, link, message} <- [
          {"unpaid, payment link", %{}, @payment_link, nil},
          {"paid, now owes more, payment link", part_paid(), @payment_link, nil},
          {"paid in full, nothing owed", paid_in_full(), nil, nil},
          {"paid, now owes less",
           %{
             amount_paid: Decimal.new("70.00"),
             balance: Decimal.new("-6.00"),
             payments: [
               %{amount: Decimal.new("70.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}
             ]
           }, nil, nil},
          {"pickup, invoice after pickup", Map.put(pickup(), :payment_terms, :invoice), nil, nil},
          {"with a message from Jennie", %{}, @payment_link, message(locale)}
        ] do
      {"Order updated", title, :order_updated, Email.order_updated(order(attrs, locale), link, message)}
    end
  end

  defp payment_received(locale) do
    orders =
      for {title, attrs, amount, message} <- [
            {"order paid in full through the payment link", paid_in_full(), "64.00", nil},
            {"order part paid, some still owed", part_paid(), "20.00", nil},
            {"order, with a message from Jennie", paid_in_full(), "64.00", message(locale)}
          ] do
        {"Payment received", title, :payment_received,
         Email.payment_received(order(attrs, locale), Decimal.new(amount), message)}
      end

    bookings =
      for {title, attrs} <- [
            {"booking paid before the course", %{}},
            {"booking for 2 paid after the course", %{seats: 2, course: %{date: ~D[2020-11-20]}}}
          ] do
        registration = registration(attrs, locale)
        amount = Decimal.mult(Decimal.new("45.00"), registration.seats)
        registration = %{registration | amount_paid: amount, balance: Decimal.new(0)}

        {"Payment received", title, :payment_received, Email.payment_received(registration, amount)}
      end

    orders ++ bookings
  end

  defp purchase_receipt(locale) do
    handed_over = Map.merge(paid_in_full(), %{fulfillment_status: :fulfilled, gift: false, recipient_name: nil})

    [
      {"Purchase receipt", "handed over and paid in full", :purchase_receipt,
       Email.purchase_receipt(order(handed_over, locale))},
      {"Purchase receipt", "with a message from Jennie, no customer first name", :purchase_receipt,
       Email.purchase_receipt(order(Map.put(handed_over, :customer_first_name, nil), locale), message(locale))}
    ]
  end

  defp payment_reminder(locale) do
    [
      {"Payment reminder", "order, unpaid", :payment_reminder,
       Email.payment_reminder(order(%{}, locale), @payment_link)},
      {"Payment reminder", "order part paid, with a message from Jennie", :payment_reminder,
       Email.payment_reminder(order(part_paid(), locale), @payment_link, message(locale))},
      {"Payment reminder", "booking for 2 after the course", :payment_reminder,
       Email.payment_reminder(
         registration(%{seats: 2, balance: Decimal.new("90.00"), course: %{date: ~D[2020-11-20]}}, locale),
         @payment_link
       )}
    ]
  end

  defp subscription_charged(locale) do
    for {title, attrs} <- [{"delivery", %{}}, {"pickup", pickup()}] do
      attrs =
        %{origin: :subscription, gift: false, recipient_name: nil, recipient_first_name: nil}
        |> Map.merge(attrs)
        |> Map.merge(%{amount_paid: Decimal.new("59.00"), balance: Decimal.new(0)})

      {"Subscription delivery charged", title, :subscription_charged,
       Email.subscription_charged(subscription_order(attrs, locale))}
    end
  end

  defp subscription_payment_failed(locale) do
    for {title, attrs} <- [
          {"delivery", %{}},
          {"pickup, no customer first name", Map.put(pickup(), :customer_first_name, nil)}
        ] do
      attrs = Map.merge(%{origin: :subscription, gift: false, recipient_name: nil, recipient_first_name: nil}, attrs)

      {"Subscription payment failed", title, :subscription_payment_failed,
       Email.subscription_payment_failed(subscription_order(attrs, locale), @payment_link)}
    end
  end

  defp pickup do
    %{
      fulfillment_method: :pickup,
      fulfillment_fee: nil,
      grand_total: Decimal.new("54.00"),
      balance: Decimal.new("54.00"),
      recipient_name: nil,
      delivery_address: nil
    }
  end

  defp part_paid do
    %{
      amount_paid: Decimal.new("20.00"),
      balance: Decimal.new("44.00"),
      payments: [%{amount: Decimal.new("20.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}]
    }
  end

  defp paid_in_full do
    %{
      amount_paid: Decimal.new("64.00"),
      balance: Decimal.new(0),
      payments: [%{amount: Decimal.new("64.00"), payment_method_type: "card", card_brand: "visa", card_last4: "4242"}]
    }
  end

  # A subscription order has one line: the subscribed product.
  defp subscription_order(attrs, locale) do
    order = order(attrs, locale)
    %{order | line_items: [hd(order.line_items)]}
  end

  defp card_message(locale) do
    cond do
      String.starts_with?(locale, "fi") -> "Hyvää syntymäpäivää!"
      String.starts_with?(locale, "sv") -> "Grattis på födelsedagen!"
      true -> "Happy birthday!"
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
           }},
          {"delivery, discount only", %{first_order_discounted?: true, card_message: nil}},
          {"delivery, card message only", %{first_order_discounted?: false, card_message: "Thinking of you!"}}
        ] do
      {"Subscription set up", title, :subscription_set_up, Email.subscription_set_up(subscription(attrs, locale))}
    end
  end

  defp subscription_cancelled(locale) do
    for {title, attrs, charged_on, message} <- [
          {"a delivery already charged still comes", %{}, ~D[2026-11-14], nil},
          {"nothing charged yet, with a message from Jennie", %{}, nil, message(locale)},
          {"pickup already charged, no first name",
           %{fulfillment_option: %{fulfillment_method: :pickup}, user: %{email: "maria@example.com", first_name: nil}},
           ~D[2026-11-14], nil}
        ] do
      {"Subscription cancelled", title, :subscription_cancelled,
       Email.subscription_cancelled(subscription(attrs, locale), charged_on, message)}
    end
  end

  defp subscription_cancellation_confirmed(locale) do
    for {title, attrs, charged_on} <- [
          {"a delivery already charged still comes", %{}, ~D[2026-11-28]},
          {"nothing charged yet", %{}, nil},
          {"pickup already charged", %{fulfillment_option: %{fulfillment_method: :pickup}}, ~D[2026-11-28]}
        ] do
      {"Subscription cancellation confirmed", title, :subscription_cancellation_confirmed,
       Email.subscription_cancellation_confirmed(subscription(attrs, locale), charged_on)}
    end
  end

  defp subscription_heads_up(locale) do
    for {title, attrs} <- [
          {"delivery", %{}},
          {"pickup, every 4 weeks",
           %{
             fulfillment_option: %{fulfillment_method: :pickup},
             delivery_address: nil,
             interval_weeks: 4,
             first_order_fulfillment_fee: Decimal.new(0)
           }}
        ] do
      {"Subscription heads-up", title, :subscription_heads_up, Email.subscription_heads_up(subscription(attrs, locale))}
    end
  end

  defp order_delivered(locale) do
    for {title, attrs} <- [
          {"gift to a named recipient", %{}},
          {"gift without a recipient name", %{recipient_first_name: nil}},
          {"not a gift, recipient name filled in", %{gift: false}},
          {"no customer first name", %{customer_first_name: nil}}
        ] do
      {"Delivered", title, :order_delivered, Email.order_delivered(order(attrs, locale))}
    end ++
      [
        {"Delivered", "with a message from Jennie", :order_delivered,
         Email.order_delivered(order(%{}, locale), message(locale))}
      ]
  end

  defp order_left_at_door(locale) do
    for {title, attrs} <- [
          {"gift to a named recipient", %{}},
          {"not a gift", %{gift: false}}
        ] do
      {"Left at the door", title, :order_left_at_door,
       Email.order_left_at_door(order(attrs, locale), "fictional-jpeg-bytes")}
    end
  end

  defp order_cancelled(locale) do
    paid = %{amount_paid: Decimal.new("64.00"), balance: Decimal.new(0)}
    refunded = fn amount -> %{refunded: Decimal.new(amount), to_return: Decimal.new(0)} end

    [
      {"Order cancelled", "refunded to a card, with a message from Jennie", :cancelled,
       Email.cancelled(
         order(Map.merge(paid, %{payments: [card_payment("64.00")], cancellation_reason: reason(locale)}), locale),
         refunded.("64.00")
       )},
      {"Order cancelled", "part paid by card, part in cash", :cancelled,
       Email.cancelled(
         order(Map.merge(paid, %{payments: [card_payment("34.00"), cash_payment("30.00")]}), locale),
         %{refunded: Decimal.new("34.00"), to_return: Decimal.new("30.00")}
       )},
      {"Order cancelled", "nothing to refund, no customer first name", :cancelled,
       Email.cancelled(order(%{customer_first_name: nil, payments: []}, locale), refunded.("0"))}
    ]
  end

  defp cancellation_confirmed(locale) do
    paid = %{amount_paid: Decimal.new("64.00"), balance: Decimal.new(0)}

    for {title, payments} <- [
          {"refunded to a card", [card_payment("64.00")]},
          {"refunded to MobilePay", [mobilepay_payment("64.00")]},
          {"refunded, paid more than one way", [card_payment("34.00"), mobilepay_payment("30.00")]}
        ] do
      {"Cancellation confirmed", title, :cancellation_confirmed,
       Email.cancellation_confirmed(
         order(Map.merge(paid, %{payments: payments}), locale),
         %{refunded: Decimal.new("64.00"), to_return: Decimal.new(0)}
       )}
    end
  end

  defp card_payment(amount),
    do: %{
      amount: Decimal.new(amount),
      method: :stripe,
      payment_method_type: "card",
      card_brand: "visa",
      card_last4: "4242"
    }

  defp mobilepay_payment(amount),
    do: %{
      amount: Decimal.new(amount),
      method: :stripe,
      payment_method_type: "mobilepay",
      card_brand: nil,
      card_last4: nil
    }

  defp cash_payment(amount),
    do: %{amount: Decimal.new(amount), method: :cash, payment_method_type: nil, card_brand: nil, card_last4: nil}

  defp course_confirmation(locale) do
    for {title, attrs} <- [
          {"paid, full refund until 7 days before", %{}},
          {"2 places, half kept after 10 days before",
           %{
             seats: 2,
             amount_paid: Decimal.new("90.00"),
             course: %{cancellation_days: 10, cancellation_fee_percent: 50}
           }},
          {"no first name, no refund after 7 days before", %{first_name: nil, course: %{cancellation_fee_percent: 100}}}
        ] do
      registration =
        registration(Map.merge(%{balance: Decimal.new(0), amount_paid: Decimal.new("45.00")}, attrs), locale)

      {"Booking confirmed", title, :course_confirmation, Email.course_confirmation(registration)}
    end
  end

  defp course_payment_link(locale) do
    for {title, attrs, message} <- [
          {"awaiting payment", %{status: :awaiting_payment}, nil},
          {"2 places, with a message from Jennie",
           %{status: :awaiting_payment, seats: 2, balance: Decimal.new("90.00")}, message(locale)},
          {"no first name", %{status: :awaiting_payment, first_name: nil}, nil}
        ] do
      {"Course payment link", title, :course_payment_link,
       Email.course_payment_link(registration(attrs, locale), @payment_link, message)}
    end
  end

  defp course_reminder(locale) do
    for {title, attrs, payment_link} <- [
          {"paid", %{status: :confirmed, balance: Decimal.new(0)}, nil},
          {"2 places awaiting payment", %{status: :awaiting_payment, seats: 2, balance: Decimal.new("90.00")},
           @payment_link},
          {"no first name", %{status: :confirmed, balance: Decimal.new(0), first_name: nil}, nil}
        ] do
      {"Course reminder", title, :course_reminder, Email.course_reminder(registration(attrs, locale), payment_link)}
    end
  end

  defp order_refunded(locale) do
    for {title, payments, method, note} <- [
          {"to a card through Stripe, with a message from Jennie", [card_payment("64.00")], :stripe, reason(locale)},
          {"to MobilePay through Stripe", [mobilepay_payment("64.00")], :stripe, nil},
          {"handed back in cash", [], :cash, nil},
          {"to a card on the card reader", [], :zettle, nil},
          {"by MobilePay to the customer's number", [], :mobilepay, nil},
          {"to the customer's bank account", [], :zervant, nil}
        ] do
      refund = %{amount: Decimal.new("20.00"), payment_method: method, note: note}
      {"Order refunded", title, :refunded, Email.refunded(order(%{payments: payments}, locale), refund)}
    end
  end

  defp booking_refunded(locale) do
    [
      {"Booking refunded", "to a card through Stripe", :refunded,
       Email.refunded(
         registration(%{payments: [card_payment("45.00")]}, locale),
         %{amount: Decimal.new("45.00"), payment_method: :stripe, note: nil}
       )},
      {"Booking refunded", "handed back in cash, with a message from Jennie", :refunded,
       Email.refunded(
         registration(%{payments: []}, locale),
         %{amount: Decimal.new("45.00"), payment_method: :cash, note: reason(locale)}
       )}
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
          {"refunded to a card", %{payments: [card]}, %{refunded: Decimal.new("45.00"), to_return: Decimal.new(0)}},
          {"with a reason, paid in cash", %{payments: [cash], cancellation_reason: reason(locale)},
           %{refunded: Decimal.new(0), to_return: Decimal.new("45.00")}},
          {"nothing paid, no first name", %{first_name: nil, payments: []},
           %{refunded: Decimal.new(0), to_return: Decimal.new(0)}}
        ] do
      {"Booking cancelled", title, :cancelled, Email.cancelled(registration(attrs, locale), money)}
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
      {"Wedding enquiry copy", "everything filled in", :wedding_enquiry, Email.wedding_enquiry(full)},
      {"Wedding enquiry copy", "only the required fields", :wedding_enquiry, Email.wedding_enquiry(minimal)}
    ]
  end

  defp account_and_newsletter(locale) do
    promo = %{code: "WELCOME-7K2P", expiration_date: ~D[2026-11-18]}

    [
      {"Newsletter welcome", "with promo code", :newsletter_welcome,
       Email.newsletter_welcome("maria@example.com", promo, locale)},
      {"Already subscribed", "code still usable", :already_subscribed,
       Email.already_subscribed("maria@example.com", promo, locale)},
      {"Already subscribed", "code used or expired", :already_subscribed,
       Email.already_subscribed("maria@example.com", nil, locale)},
      {"Account", "sign-in code", :otp_sign_in, Email.otp_sign_in("maria@example.com", "482913")},
      {"Account", "email change code", :email_change_code, Email.email_change_code("maria@example.com", "730184")}
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
        card_message: nil,
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
          location_address: "Storgatan 1, 65100 Vaasa",
          cancellation_days: 7,
          cancellation_fee_percent: 0
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

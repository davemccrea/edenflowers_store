defmodule EdenflowersWeb.PaymentLinkStatesTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.ShopTime
  alias EdenflowersWeb.PaymentLink

  @order_money [
    %{name: :unpaid, payments: [], state: :unpaid, held: 0, refund_due: 0},
    %{name: :partial, payments: [{3000, false}], state: :unpaid, held: 3000, refund_due: 0},
    %{name: :paid, payments: [{8850, false}], state: :paid, held: 8850, refund_due: 0},
    %{name: :overpaid, payments: [{9850, false}], state: :paid, held: 9850, refund_due: 1000},
    %{name: :refunded, payments: [{8850, false}, {-8850, true}], state: :refunded, held: 0, refund_due: 0},
    %{name: :goodwill_refund, payments: [{8850, false}, {-2000, true}], state: :paid, held: 6850, refund_due: 0}
  ]

  # Money states are independent of delivery method; retain the intersections
  # where fulfillment copy or cancellation changes what the customer is told.
  for {method, fulfillment, money_name} <- [
        {:pickup, :pending, :unpaid},
        {:pickup, :pending, :partial},
        {:pickup, :pending, :paid},
        {:pickup, :pending, :overpaid},
        {:pickup, :pending, :refunded},
        {:pickup, :pending, :goodwill_refund},
        {:delivery, :pending, :partial},
        {:pickup, :fulfilled, :paid},
        {:delivery, :fulfilled, :paid},
        {:pickup, :fulfilled, :unpaid},
        {:delivery, :fulfilled, :unpaid},
        {:pickup, :cancelled, :unpaid},
        {:pickup, :cancelled, :refunded},
        {:delivery, :cancelled, :overpaid},
        {:delivery, :cancelled, :goodwill_refund}
      ] do
    @tag method: method, fulfillment: fulfillment, money: Enum.find(@order_money, &(&1.name == money_name))
    test "order #{method}, #{fulfillment}, #{money_name} has truthful copy and payment actions", ctx do
      order =
        placed_order(
          fulfillment_method: ctx.method,
          fulfillment_status: ctx.fulfillment,
          fulfillment_date: Date.add(ShopTime.today(), -1),
          delivery_address: "Myrvägen 1, Vaasa",
          payment_link_token: token()
        )

      add_payments(:order_id, order.id, ctx.money.payments)
      {:ok, view, _html} = live(ctx.conn, PaymentLink.path_for(order))

      cancelled? = ctx.fulfillment == :cancelled
      paid? = not cancelled? and ctx.money.state == :paid
      refunded? = not cancelled? and ctx.money.state == :refunded
      payable? = not cancelled? and ctx.money.state == :unpaid

      assert has_element?(view, "[data-testid=pay-cancelled]") == cancelled?
      assert has_element?(view, "[data-testid=pay-refunded]") == refunded?
      assert has_element?(view, "[data-testid=pay-paid]") == paid?
      assert has_element?(view, "#pay-form") == payable?
      assert has_element?(view, "#main-content .flower-bloom") == paid?
      refute has_element?(view, "[data-testid=pay-confirming]")
      assert has_element?(view, "[data-testid=pay-thanks]") == (paid? and ctx.fulfillment == :fulfilled)

      expected_title =
        cond do
          cancelled? -> "Order cancelled"
          refunded? -> "Order refunded"
          paid? -> "Thank you for your order"
          true -> "Pay for your order"
        end

      assert page_title(view) =~ expected_title
      assert has_element?(view, "hgroup p", "Order #{order.order_reference}")

      if paid? and ctx.fulfillment == :fulfilled do
        assert has_element?(view, "p[data-testid=pay-thanks]", "I hope you're happy with it.")
        refute has_element?(view, "[data-testid=pay-fulfillment]")
      end

      if ctx.money.name == :partial and not cancelled? do
        assert has_element?(view, "[data-testid=pay-total]", "88,50")
        assert has_element?(view, "dt", "Paid so far")
        assert has_element?(view, "[data-testid=pay-balance]", "58,50")
        assert has_element?(view, ~s|#pay-form[data-amount="5850"]|)
        refute has_element?(view, "dt", "Total paid")
      end

      if payable? and ctx.fulfillment == :fulfilled do
        verb = if ctx.method == :pickup, do: "collected", else: "delivered"
        assert has_element?(view, "[data-testid=pay-fulfillment]", "has been #{verb}")
        refute render(view) =~ "Ready to collect"
        refute render(view) =~ "Delivery on"
      end

      if cancelled? or refunded? do
        refute has_element?(view, "[data-testid=pay-fulfillment]")
        refute has_element?(view, "[data-testid=pay-thanks]")
      end

      if paid? do
        assert has_element?(view, "[data-testid=pay-total]", currency(ctx.money.held))
        refute render(view) =~ "Paid so far"
      end

      assert_refund_due(view, if(cancelled?, do: ctx.money.held, else: ctx.money.refund_due))
    end
  end

  @booking_money [
    %{name: :unpaid, payments: [], state: :unpaid, held: 0, refund_due: 0},
    %{name: :partial, payments: [{5000, false}], state: :unpaid, held: 5000, refund_due: 0},
    %{name: :paid, payments: [{17_000, false}], state: :paid, held: 17_000, refund_due: 0},
    %{name: :overpaid, payments: [{19_000, false}], state: :paid, held: 19_000, refund_due: 2000},
    %{name: :refunded, payments: [{17_000, false}, {-17_000, true}], state: :refunded, held: 0, refund_due: 0},
    %{name: :goodwill_refund, payments: [{17_000, false}, {-3000, true}], state: :paid, held: 14_000, refund_due: 0}
  ]

  for {period, status, money_name} <- [
        {:future, :confirmed, :unpaid},
        {:future, :confirmed, :partial},
        {:future, :confirmed, :paid},
        {:future, :confirmed, :overpaid},
        {:future, :confirmed, :refunded},
        {:future, :confirmed, :goodwill_refund},
        {:past, :confirmed, :unpaid},
        {:past, :confirmed, :paid},
        {:future, :cancelled, :unpaid},
        {:future, :cancelled, :paid},
        {:future, :cancelled, :refunded},
        {:future, :cancelled, :goodwill_refund}
      ] do
    @tag period: period, status: status, money: Enum.find(@booking_money, &(&1.name == money_name))
    test "#{period} course, #{status}, #{money_name} has truthful copy and payment actions", ctx do
      course = generate(course(date: Date.add(ShopTime.today(), if(ctx.period == :past, do: -1, else: 1))))

      registration =
        generate(
          course_registration(
            course_id: course.id,
            status: ctx.status,
            seats: 2,
            amount: Decimal.new("170.00"),
            payment_link_token: token()
          )
        )

      add_payments(:course_registration_id, registration.id, ctx.money.payments)
      {:ok, view, _html} = live(ctx.conn, PaymentLink.path_for(registration))

      cancelled? = ctx.status == :cancelled
      paid? = not cancelled? and ctx.money.state == :paid
      refunded? = not cancelled? and ctx.money.state == :refunded
      payable? = not cancelled? and ctx.money.state == :unpaid

      assert has_element?(view, "[data-testid=pay-cancelled]") == cancelled?
      assert has_element?(view, "[data-testid=pay-refunded]") == refunded?
      assert has_element?(view, "[data-testid=pay-paid]") == paid?
      assert has_element?(view, "#pay-form") == payable?
      assert has_element?(view, "#main-content .flower-bloom") == paid?
      assert has_element?(view, "[data-testid=pay-booked]") == (paid? and ctx.period == :future)
      refute has_element?(view, "[data-testid=pay-confirming]")

      if ctx.money.name == :unpaid and not cancelled? do
        assert has_element?(view, "[data-testid=pay-total]", "170,00")
        refute has_element?(view, "[data-testid=pay-balance]")
        refute render(view) =~ "Paid so far"
      end

      if paid? do
        assert has_element?(view, "[data-testid=pay-total]", currency(ctx.money.held))
        refute render(view) =~ "Paid so far"
      end

      expected_title =
        cond do
          cancelled? -> "Booking cancelled"
          refunded? -> "Booking refunded"
          paid? -> "Your booking"
          true -> "Pay for your booking"
        end

      assert page_title(view) =~ expected_title
      if ctx.period == :past, do: refute(render(view) =~ "You're booked")
      assert_refund_due(view, if(cancelled?, do: ctx.money.held, else: ctx.money.refund_due))
    end
  end

  for kind <- [:order, :course] do
    @tag kind: kind
    test "#{kind}: a received partial payment ends confirming and offers only the remaining balance", ctx do
      record = unpaid_record(ctx.kind)
      {:ok, view, _html} = live(ctx.conn, PaymentLink.path_for(record) <> "?redirect_status=succeeded")
      assert has_element?(view, "[data-testid=pay-confirming]")

      {foreign_key, topic, remaining} =
        case ctx.kind do
          :order -> {:order_id, "order:paid:#{record.id}", "58,50"}
          :course -> {:course_registration_id, "course_registration:paid:#{record.id}", "140,00"}
        end

      add_payments(foreign_key, record.id, [{3000, false}])
      EdenflowersWeb.Endpoint.broadcast(topic, "paid", %{})

      assert has_element?(view, "#pay-form")
      assert has_element?(view, "[data-testid=pay-balance]", remaining)
      assert page_title(view) =~ "Pay for your"
      refute has_element?(view, "[data-testid=pay-confirming]")
      refute has_element?(view, "[data-testid=pay-paid]")
    end
  end

  for kind <- [:order, :course], paid? <- [false, true] do
    @tag kind: kind, paid?: paid?
    test "#{kind}: failed return only requests a retry while payment is still owed (paid=#{paid?})", ctx do
      record = unpaid_record(ctx.kind)

      if ctx.paid? do
        {key, amount} = if ctx.kind == :order, do: {:order_id, 8850}, else: {:course_registration_id, 17_000}
        add_payments(key, record.id, [{amount, false}])
      end

      {:ok, view, _html} = live(ctx.conn, PaymentLink.path_for(record) <> "?redirect_status=failed")

      assert has_element?(view, "#pay-form") == not ctx.paid?
      assert has_element?(view, "#flash-error", "Your payment didn't go through") == not ctx.paid?
      refute has_element?(view, "[data-testid=pay-confirming]")
    end
  end

  for period <- [:future, :past], partial? <- [false, true] do
    @tag period: period, partial?: partial?
    test "#{period} invite or booking still owing can be paid (partial=#{partial?})", ctx do
      course = generate(course(date: Date.add(ShopTime.today(), if(ctx.period == :past, do: -1, else: 1))))

      registration =
        generate(
          course_registration(
            course_id: course.id,
            status: if(ctx.partial?, do: :confirmed, else: :pending),
            seats: 2,
            amount: Decimal.new("170.00"),
            payment_link_token: token()
          )
        )

      if ctx.partial?, do: add_payments(:course_registration_id, registration.id, [{5000, false}])
      {:ok, view, _html} = live(ctx.conn, PaymentLink.path_for(registration))

      assert has_element?(view, "h1", "Pay for your booking")
      assert has_element?(view, "#pay-form")
      assert has_element?(view, "[data-testid=pay-balance]") == ctx.partial?
      refute has_element?(view, "[data-testid=pay-booked]")
      refute has_element?(view, "[data-testid=pay-paid]")
    end
  end

  test "a confirmed booking with no remaining places never promises a place", %{conn: conn} do
    registration =
      generate(
        course_registration(
          status: :confirmed,
          seats: 2,
          removed_seats: 2,
          amount: Decimal.new("170.00"),
          payment_link_token: token()
        )
      )

    {:ok, view, _html} = live(conn, PaymentLink.path_for(registration))

    refute has_element?(view, "[data-testid=pay-booked]")
    refute has_element?(view, "#pay-form")
  end

  for kind <- [:order, :course] do
    @tag kind: kind
    test "#{kind}: cancelling with money retained does not invent a refund", ctx do
      record = unpaid_record(ctx.kind)

      record =
        case ctx.kind do
          :order -> Ash.Seed.update!(record, %{fulfillment_status: :cancelled, kept_amount: Decimal.new("30.00")})
          :course -> Ash.Seed.update!(record, %{status: :cancelled, kept_amount: Decimal.new("30.00")})
        end

      key = if ctx.kind == :order, do: :order_id, else: :course_registration_id
      add_payments(key, record.id, [{3000, false}])
      {:ok, view, _html} = live(ctx.conn, PaymentLink.path_for(record))

      assert has_element?(view, "[data-testid=pay-cancelled]")
      refute has_element?(view, "[data-testid=pay-refunded]")
      refute has_element?(view, "[data-testid=pay-refund-due]")
      refute has_element?(view, "[data-testid=pay-paid]")
      refute has_element?(view, "#pay-form")
    end
  end

  for {locale, thanks} <- [{"sv-FI", "Tack"}, {"fi", "Kiitos"}, {"en-GB", "Thank you"}] do
    @tag locale: locale, thanks: thanks
    test "past course payment confirmation uses #{locale} without a future booking promise", ctx do
      course = generate(course(date: Date.add(ShopTime.today(), -1)))

      registration =
        generate(
          course_registration(course_id: course.id, status: :confirmed, locale: ctx.locale, payment_link_token: token())
        )

      add_payments(:course_registration_id, registration.id, [{8500, false}])
      {:ok, view, _html} = live(ctx.conn, PaymentLink.path_for(registration))

      assert has_element?(view, "h1", ctx.thanks)
      refute has_element?(view, "[data-testid=pay-booked]")
      refute has_element?(view, "[data-testid=pay-confirming]")
      refute has_element?(view, "#pay-form")
    end
  end

  for kind <- [:order, :course], outcome <- [:paid, :cancelled, :refunded] do
    @tag kind: kind, outcome: outcome
    test "#{kind}: a stale successful return cannot override #{outcome}", ctx do
      record = unpaid_record(ctx.kind)
      {key, total} = if ctx.kind == :order, do: {:order_id, 8850}, else: {:course_registration_id, 17_000}
      add_payments(key, record.id, [{total, false}])
      if ctx.outcome == :refunded, do: add_payments(key, record.id, [{-total, true}])

      if ctx.outcome == :cancelled do
        case ctx.kind do
          :order -> Ash.Seed.update!(record, %{fulfillment_status: :cancelled})
          :course -> Ash.Seed.update!(record, %{status: :cancelled})
        end
      end

      {:ok, view, _html} = live(ctx.conn, PaymentLink.path_for(record) <> "?redirect_status=succeeded")

      assert has_element?(view, "[data-testid=pay-#{ctx.outcome}]")
      refute has_element?(view, "[data-testid=pay-confirming]")
      refute has_element?(view, "#pay-form")
      refute has_element?(view, ".flower-waiting")
    end
  end

  for kind <- [:order, :course] do
    @tag kind: kind
    test "#{kind}: a zero-cost purchase never asks for payment", ctx do
      record = unpaid_record(ctx.kind)

      record =
        case ctx.kind do
          :course ->
            Ash.Seed.update!(record, %{amount: Decimal.new("0")})

          :order ->
            for line <- Ash.load!(record, :line_items, authorize?: false).line_items do
              Ash.Seed.update!(line, %{unit_price: Decimal.new("0")})
            end

            Ash.Seed.update!(record, %{quoted_fulfillment_fee: Decimal.new("0")})
        end

      {:ok, view, _html} = live(ctx.conn, PaymentLink.path_for(record))

      assert has_element?(view, "[data-testid=pay-paid]")
      assert has_element?(view, "[data-testid=pay-total]", "0,00")
      refute has_element?(view, "#pay-form")
      refute has_element?(view, "[data-testid=pay-refunded]")
    end
  end

  test "an unplaced checkout cart is not a paid order" do
    cart = generate(order(state: :payment))
    refute Ash.load!(cart, :paid?, authorize?: false).paid?
  end

  test "an invite with no balance does not ask for payment or pretend it is confirming", %{conn: conn} do
    registration =
      generate(course_registration(status: :pending, amount: Decimal.new("0"), payment_link_token: token()))

    {:ok, view, _html} = live(conn, PaymentLink.path_for(registration) <> "?redirect_status=succeeded")

    assert has_element?(view, "h1", "Your booking")
    refute has_element?(view, "[data-testid=pay-booked]")
    refute has_element?(view, "[data-testid=pay-confirming]")
    refute has_element?(view, "#pay-form")
  end

  defp unpaid_record(:order), do: placed_order(payment_link_token: token())

  defp unpaid_record(:course) do
    generate(
      course_registration(status: :confirmed, seats: 2, amount: Decimal.new("170.00"), payment_link_token: token())
    )
  end

  defp add_payments(foreign_key, id, payments) do
    for {cents, goodwill} <- payments do
      generate(payment([{foreign_key, id}, {:amount, Decimal.div(cents, 100)}, {:goodwill, goodwill}]))
    end
  end

  defp assert_refund_due(view, 0), do: refute(has_element?(view, "[data-testid=pay-refund-due]"))

  defp assert_refund_due(view, cents) do
    assert has_element?(view, "[data-testid=pay-refund-due]", currency(cents))
    assert render(view) =~ "To be refunded"
    refute has_element?(view, "#pay-form")
  end

  defp currency(cents), do: Edenflowers.Format.currency(Decimal.div(cents, 100), "en-GB")
  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
end

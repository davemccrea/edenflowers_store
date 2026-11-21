defmodule EdenflowersWeb.Admin.OverviewLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Generator

  alias Edenflowers.Fulfillment.Weekday
  alias EdenflowersWeb.Admin.OverviewLive

  describe "days" do
    setup :log_in_admin

    defp open_order(name, method, days_from_today) do
      generate(
        order(
          state: :placed,
          customer_name: name,
          fulfillment_method: method,
          fulfillment_date: Date.add(Edenflowers.ShopTime.today(), days_from_today),
          fulfillment_status: :pending
        )
      )
    end

    test "prepares an order in place and keeps it visible", %{conn: conn, admin: admin} do
      order = open_order("To prepare", :delivery, 0)
      {:ok, view, _html} = live(conn, ~p"/admin")
      row = "#day-order-#{order.id}"

      mark = ~s|#{row} button[aria-label="Mark order #{order.order_reference} as ready"]|
      undo = ~s|#{row} button[aria-label="Undo ready for order #{order.order_reference}"]|

      view |> element(mark) |> render_click()
      assert_push_event(view, "order-ready", %{})
      assert Edenflowers.Orders.get_order_for_admin!(order.id, actor: admin).fulfillment_status == :ready

      eventually(fn ->
        assert has_element?(view, row, "Ready for delivery")
        assert has_element?(view, "#{row} a", "To prepare")
        refute has_element?(view, mark)
      end)

      view |> element("#flash-success #undo-ready", "Undo") |> render_click()
      assert Edenflowers.Orders.get_order_for_admin!(order.id, actor: admin).fulfillment_status == :pending
      assert has_element?(view, "#flash-success", "Order returned to To make.")
      refute has_element?(view, "#undo-ready")

      eventually(fn -> assert has_element?(view, mark) end)

      view |> element(mark) |> render_click()
      eventually(fn -> assert has_element?(view, undo) end)

      view |> element(undo) |> render_click()
      assert Edenflowers.Orders.get_order_for_admin!(order.id, actor: admin).fulfillment_status == :pending
      eventually(fn -> assert has_element?(view, mark) end)
    end

    test "says where a delivery goes", %{conn: conn} do
      order =
        generate(
          order(
            state: :placed,
            customer_name: "Far Away",
            fulfillment_method: :delivery,
            fulfillment_date: Edenflowers.ShopTime.today(),
            fulfillment_status: :pending,
            delivery_address: "Gerbyntie 16, 65230 Vaasa",
            geocoded_address: "Gerbyntie 16, 65230 Vaasa",
            geocoded_address_sv: "Gerbyvägen 16, 65230 Vasa",
            distance: 4900
          )
        )

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#day-order-#{order.id}", "65230 Vasa · 4.9 km")
    end

    test "shows today's weather under the greeting", %{conn: conn} do
      now = DateTime.to_iso8601(DateTime.utc_now())
      on_exit(fn -> :persistent_term.erase(Edenflowers.External.WeatherAPI) end)

      Req.Test.stub(Edenflowers.External.WeatherAPI, fn conn ->
        Req.Test.json(conn, %{
          "properties" => %{
            "timeseries" => [
              %{
                "time" => now,
                "data" => %{
                  "instant" => %{"details" => %{"air_temperature" => -2.2}},
                  "next_1_hours" => %{"summary" => %{"symbol_code" => "heavyrain"}}
                }
              }
            ]
          }
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/admin")

      render_async(view)
      assert has_element?(view, "header #today-weather", "H -2° L -2°")
      assert has_element?(view, ~s(header #today-weather img[alt="Rain"][src*="/images/weather/heavyrain"]))
    end

    test "refreshes a note from another page", %{conn: conn, admin: admin} do
      order = open_order("New note", :pickup, 0)
      {:ok, view, _html} = live(conn, ~p"/admin")
      {:ok, _order} = Edenflowers.Orders.update_florist_note(order, %{florist_note: "White flowers"}, actor: admin)

      eventually(fn -> assert has_element?(view, "#day-order-#{order.id}", "White flowers") end)
    end

    test "business notifications refresh all saved data after the day changes", %{admin: admin} do
      today = Edenflowers.ShopTime.today()
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_user: admin}}
      {:ok, socket} = OverviewLive.mount(%{}, %{}, socket)
      bank_connection = socket.assigns.bank_connection
      report_month = socket.assigns.report_month

      socket =
        Phoenix.Component.assign(socket,
          today: Date.add(today, -1),
          calendar: nil,
          bank_connection: nil,
          report_month: nil
        )

      for topic <- ["admin:orders", "admin:subscriptions", "shop_calendar:changed", "admin:bank"] do
        {:noreply, pending} = OverviewLive.handle_info(%Phoenix.Socket.Broadcast{topic: topic}, socket)
        assert_receive {:admin_refresh, :overview}
        {:noreply, refreshed} = OverviewLive.handle_info({:admin_refresh, :overview}, pending)

        assert refreshed.assigns.today == today
        assert hd(refreshed.assigns.days) == today
        assert refreshed.assigns.calendar
        assert refreshed.assigns.bank_connection == bank_connection
        assert refreshed.assigns.report_month == report_month
      end
    end

    test "refreshes a stale order without celebrating a readiness change that fails", %{conn: conn} do
      order = open_order("Already prepared", :delivery, 0)
      {:ok, view, _html} = live(conn, ~p"/admin")
      Ash.Seed.update!(order, %{fulfillment_status: :ready})

      render_click(view, "mark_ready", %{"id" => order.id})

      refute_push_event(view, "order-ready", %{})
      assert has_element?(view, "#flash-error", "The order has changed")
      assert has_element?(view, "#day-order-#{order.id}", "Ready for delivery")
      refute has_element?(view, ~s|#day-order-#{order.id} button[phx-click="mark_ready"]|)
    end

    test "rejects a cart id sent as a readiness event", %{conn: conn, admin: admin} do
      cart = generate(order())
      {:ok, view, _html} = live(conn, ~p"/admin")

      render_click(view, "mark_ready", %{"id" => cart.id})

      refute_push_event(view, "order-ready", %{})
      assert has_element?(view, "#flash-error", "The order has changed")
      unchanged = Edenflowers.Orders.get_order_by_id!(cart.id, actor: admin)
      assert unchanged.state == cart.state
      assert unchanged.fulfillment_status == cart.fulfillment_status
    end

    test "lists today's orders by method, and only today's", %{conn: conn} do
      open_order("Today Delivery", :delivery, 0)
      open_order("Today Pickup", :pickup, 0)
      open_order("Tomorrow Pickup", :pickup, 1)
      open_order("Last Week", :pickup, -7)

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#day-orders-title", "Today")
      assert has_element?(view, "#day-orders-delivery", "Today Delivery")
      assert has_element?(view, "#day-orders-pickup", "Today Pickup")
      assert has_element?(view, "#day-orders-delivery h4 .badge", "1")
      refute has_element?(view, "#day-orders", "Tomorrow Pickup")
      refute has_element?(view, "#day-orders", "Last Week")
    end

    test "counts each day and shows the one tapped", %{conn: conn} do
      in_three_days = Date.add(Edenflowers.ShopTime.today(), 3)
      in_four_days = Date.add(Edenflowers.ShopTime.today(), 4)
      in_five_days = Date.add(Edenflowers.ShopTime.today(), 5)

      shop_calendar(
        available_days: Weekday.all(),
        disabled_dates: [in_four_days, in_five_days]
      )

      open_order("Later", :pickup, 3)
      open_order("Taken anyway", :pickup, 5)
      open_order("Too far", :pickup, 9)

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#day-#{in_three_days} .badge", "1")
      assert has_element?(view, ~s|#day-#{in_three_days} a[aria-label$=", 1 order"]|)
      refute has_element?(view, "#day-#{in_four_days} .badge")
      assert has_element?(view, ~s|#day-#{in_four_days} a[aria-label$=", Closed"]|)
      assert has_element?(view, ~s|#day-#{in_five_days} a[aria-label$=", Closed, 1 order"]|)
      assert has_element?(view, "#day-#{in_five_days} .badge", "1")
      refute has_element?(view, "#day-#{Date.add(in_three_days, 6)}")

      view |> element("#day-#{in_three_days} a") |> render_click()
      assert_patch(view, ~p"/admin?#{[day: Date.to_iso8601(in_three_days)]}")
      assert has_element?(view, "#day-orders-pickup", "Later")
      assert has_element?(view, "#day-#{in_three_days} a[aria-current]")
    end

    test "says so when a day has nothing to make", %{conn: conn} do
      open_order("Tomorrow Pickup", :pickup, 1)

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#day-orders", "Nothing to make today")

      {:ok, view, _html} = live(conn, ~p"/admin?day=#{Date.to_iso8601(Date.add(Edenflowers.ShopTime.today(), 1))}")
      refute has_element?(view, "#day-orders", "Nothing to make tomorrow")
    end

    test "falls back to today for a day off the strip", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin?day=#{Date.to_iso8601(Date.add(Edenflowers.ShopTime.today(), -1))}")

      assert has_element?(view, "#day-orders-title", "Today")
    end

    test "stops and reopens new orders for today, and only today", %{conn: conn} do
      today = Edenflowers.ShopTime.today()

      shop_calendar(
        available_days: Weekday.all(),
        same_day: true,
        order_deadline: ~T[23:59:59],
        disabled_dates: [],
        enabled_dates: []
      )

      {:ok, view, _html} = live(conn, ~p"/admin")

      view |> element("#day-orders-toggle", "Stop orders") |> render_click()
      assert today in Edenflowers.Fulfillment.get_shop_calendar!().disabled_dates
      assert has_element?(view, "#day-orders-closed")

      view |> element("#day-orders-toggle", "Reopen orders") |> render_click()
      refute today in Edenflowers.Fulfillment.get_shop_calendar!().disabled_dates

      {:ok, view, _html} = live(conn, ~p"/admin?day=#{Date.to_iso8601(Date.add(today, 1))}")
      refute has_element?(view, "#day-orders-toggle")
      render_hook(view, "toggle-date", %{"date" => Date.to_iso8601(Date.add(today, 1))})
      assert Edenflowers.Fulfillment.get_shop_calendar!().disabled_dates == []
    end

    test "offers no toggle for a day the weekly rules already close", %{conn: conn} do
      shop_calendar(same_day: false, disabled_dates: [], enabled_dates: [])

      {:ok, view, _html} = live(conn, ~p"/admin")

      refute has_element?(view, "#day-orders-toggle")
    end
  end

  test "says what an order still owes, and nothing once it's refunded in full", %{conn: conn} do
    conn = log_in(conn, generate(admin_user()) |> with_token())
    attrs = [fulfillment_date: Edenflowers.ShopTime.today(), fulfillment_status: :pending]

    unpaid = placed_order([paid: false] ++ attrs)
    part_paid = placed_order([paid: "50.00"] ++ attrs)
    # Its Balance reads the total again, but it is Settled.
    refunded = placed_order([refunded: true] ++ attrs)

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, ~s|#day-order-#{unpaid.id}|, "Unpaid")
    assert has_element?(view, ~s|#day-order-#{part_paid.id}|, "To collect 38,50")
    assert has_element?(view, ~s|a[href="/admin/orders/#{refunded.id}"]|)
    refute has_element?(view, ~s|#day-order-#{refunded.id}|, "Unpaid")
    refute has_element?(view, ~s|#day-order-#{refunded.id}|, "To collect")
  end

  test "shows an order placed elsewhere without a refresh", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin")
    refute render(view) =~ "Grace Hopper"

    generate(
      order(
        state: :placed,
        customer_name: "Grace Hopper",
        fulfillment_method: :pickup,
        fulfillment_date: Edenflowers.ShopTime.today(),
        fulfillment_status: :pending,
        grand_total: "42.00",
        ordered_at: DateTime.utc_now()
      )
    )

    EdenflowersWeb.Endpoint.broadcast("admin:orders", "finalize_checkout", %{})

    eventually(fn -> assert render_async(view, 500) =~ "Grace Hopper" end)
  end

  describe "needs attention" do
    setup :log_in_admin

    test "counts the bank payments without a receipt and links to each", %{conn: conn} do
      payment =
        Ash.Seed.seed!(Edenflowers.Bank.Transaction, %{
          bank_id: "tx-missing",
          booked_on: Date.add(Edenflowers.ShopTime.today(), -10),
          amount: Decimal.new("24.90"),
          currency: "eur",
          counterparty: "Kahvila"
        })

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#attention-missing-receipts summary .badge", "1")
      href = "/admin/expenses?payment=#{payment.id}#bank-payment-#{payment.id}"
      assert has_element?(view, ~s|#attention-missing-receipts a[href="#{href}"]|, "Kahvila")
    end

    test "is hidden when nothing needs Jennie", %{conn: conn} do
      placed_order(paid: true, fulfillment_status: :fulfilled)

      {:ok, view, _html} = live(conn, ~p"/admin")

      refute has_element?(view, "#attention")
      refute has_element?(view, "#still-owed")
    end

    test "lists overdue orders", %{conn: conn} do
      today = Edenflowers.ShopTime.today()

      overdue =
        generate(
          order(
            state: :placed,
            customer_name: "Late",
            fulfillment_date: Date.add(today, -2),
            fulfillment_status: :pending
          )
        )

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#attention-overdue-orders summary", "Overdue orders 1")
      assert has_element?(view, "#attention-overdue-orders summary .badge", "1")
      assert has_element?(view, ~s|#attention-overdue-orders a[href="/admin/orders/#{overdue.id}"]|, "Late")
    end

    test "lists subscriptions whose payment failed", %{conn: conn} do
      failed = generate(subscription(state: :payment_failed))
      generate(subscription(state: :active))

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#attention-failed-subscriptions summary", "Subscription payment failed 1")
      assert has_element?(view, ~s|#attention-failed-subscriptions a[href="/admin/subscriptions/#{failed.id}"]|)
    end

    test "refreshes subscription alerts changed elsewhere and keeps other dashboard data", %{conn: conn, admin: admin} do
      date = Date.add(Edenflowers.ShopTime.today(), 7)
      held = generate(subscription(state: :payment_failed, next_fulfillment_date: date))
      shop_calendar(disabled_dates: [date])
      overdue = placed_order(fulfillment_date: Date.add(Edenflowers.ShopTime.today(), -1))
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#attention-failed-subscriptions")
      refute has_element?(view, "#attention-closed-day-subscriptions")
      finances = render(element(view, "#revenue"))
      owed = render(element(view, "#still-owed"))

      {:ok, active} = Edenflowers.Orders.reactivate_subscription(held, actor: Edenflowers.Actors.system_actor())

      eventually(fn ->
        refute has_element?(view, "#attention-failed-subscriptions")
        assert has_element?(view, ~s|#attention-closed-day-subscriptions a[href="/admin/subscriptions/#{held.id}"]|)
        assert has_element?(view, ~s|#attention-overdue-orders a[href="/admin/orders/#{overdue.id}"]|)
      end)

      assert render(element(view, "#revenue")) == finances
      assert render(element(view, "#still-owed")) == owed
      {:ok, _paused} = Edenflowers.Orders.pause_subscription(active, actor: admin)

      eventually(fn ->
        refute has_element?(view, "#attention-closed-day-subscriptions")
        refute has_element?(view, "#attention-failed-subscriptions")
      end)
    end

    test "refreshes calendar changes made elsewhere along with subscription alerts", %{conn: conn, admin: admin} do
      date = Date.add(Edenflowers.ShopTime.today(), 5)
      closing = generate(subscription(next_fulfillment_date: date))
      failed = generate(subscription(state: :payment_failed))
      calendar = shop_calendar(available_days: Weekday.all(), disabled_dates: [], enabled_dates: [])
      {:ok, view, _html} = live(conn, ~p"/admin")
      refute has_element?(view, "#attention-closed-day-subscriptions")

      calendar = Edenflowers.Fulfillment.toggle_date!(calendar, date, actor: admin)

      eventually(fn ->
        assert has_element?(view, ~s|#day-#{date} a[aria-label$=", Closed"]|)
        assert has_element?(view, ~s|#attention-closed-day-subscriptions a[href="/admin/subscriptions/#{closing.id}"]|)
        assert has_element?(view, ~s|#attention-failed-subscriptions a[href="/admin/subscriptions/#{failed.id}"]|)
      end)

      Edenflowers.Fulfillment.toggle_date!(calendar, date, actor: admin)

      eventually(fn ->
        refute has_element?(view, ~s|#day-#{date} a[aria-label$=", Closed"]|)
        refute has_element?(view, "#attention-closed-day-subscriptions")
      end)
    end

    test "lists subscription deliveries on closed days, so Jennie can agree another day", %{conn: conn} do
      date = Date.add(Edenflowers.ShopTime.today(), 5)
      closing = generate(subscription(next_fulfillment_date: date))
      shop_calendar(disabled_dates: [date])

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(
               view,
               "#attention-closed-day-subscriptions summary",
               "Subscriptions on closed days 1"
             )

      assert has_element?(
               view,
               ~s|#attention-closed-day-subscriptions a[href="/admin/subscriptions/#{closing.id}"]|,
               Edenflowers.Format.weekday_day_month(date, "en-GB")
             )
    end

    test "flags refunds and overdue payments, and totals what orders still owe", %{conn: conn} do
      overdue = placed_order(customer_name: "Ada Lovelace", fulfillment_status: :fulfilled, payment_intent_id: nil)

      placed_order(
        customer_name: "Grace Hopper",
        fulfillment_status: :fulfilled,
        fulfillment_date: Date.add(Edenflowers.ShopTime.today(), -3),
        payment_intent_id: nil
      )

      course = generate(course(name: "Autumn wreaths"))

      registration =
        generate(
          course_registration(course_id: course.id, status: :cancelled, name: "Birgitta", amount: Decimal.new("85.00"))
        )

      generate(payment(course_registration_id: registration.id, amount: Decimal.new("85.00"), method: :cash))

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#attention-payment-overdue summary", "Payment overdue 1")
      assert has_element?(view, "#attention-payment-overdue summary", "88,50 €")
      assert has_element?(view, ~s|#attention-payment-overdue a[href="/admin/orders/#{overdue.id}"]|, "Ada Lovelace")

      assert has_element?(view, "#attention-refund summary", "To refund 1")
      assert has_element?(view, "#attention-refund summary", "85,00 €")

      assert has_element?(
               view,
               ~s|#attention-refund a[href="/admin/courses/#{registration.course_id}?booking=#{registration.id}#registration-#{registration.id}"]|,
               "Autumn wreaths"
             )

      refute has_element?(view, "#attention", "Grace Hopper")
      assert has_element?(view, "#still-owed", "177,00 €")
    end

    test "flags a booking still unpaid two weeks after its course", %{conn: conn} do
      today = Edenflowers.ShopTime.today()

      course =
        generate(course(name: "Spring posies", date: Date.add(today, -15), register_before: Date.add(today, -20)))

      generate(course_registration(course_id: course.id, status: :confirmed, name: "Birgitta"))

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#attention-payment-overdue", "Birgitta")
    end

    test "refreshes payments and refunds made while the Overview is open", %{conn: conn} do
      order = placed_order(payment_intent_id: "pi_link", fulfillment_date: Edenflowers.ShopTime.today())

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#still-owed", "88,50 €")
      assert has_element?(view, "#revenue dd", "0,00 €")

      {:ok, _order} =
        Edenflowers.Orders.record_link_payment(order, "pi_link", %{amount_paid: order.grand_total},
          actor: Edenflowers.Actors.system_actor()
        )

      eventually(fn ->
        refute has_element?(view, "#still-owed")
        assert has_element?(view, "#revenue dd", "88,50 €")
        assert has_element?(view, "#sales dd", "1")
      end)

      assert {:ok, :recorded} =
               Edenflowers.Payments.record_stripe_refund(%{
                 id: "re_overview",
                 status: "succeeded",
                 payment_intent: "pi_link",
                 amount: 1_000
               })

      eventually(fn ->
        refute has_element?(view, "#still-owed")
        assert has_element?(view, "#revenue dd", "78,50 €")
        assert has_element?(view, "#sales dd", "1")
      end)
    end
  end

  test "lists the latest confirmed bookings on upcoming courses, linked to each, and leaves out unfinished checkouts",
       %{
         conn: conn
       } do
    conn = log_in(conn, generate(admin_user()) |> with_token())
    course = generate(course(name: "Spring posies"))

    booking =
      generate(
        course_registration(
          course_id: course.id,
          status: :confirmed,
          name: "Birgitta",
          confirmed_at: DateTime.utc_now()
        )
      )

    generate(course_registration(course_id: course.id, status: :pending, name: "Halfway Hanna"))

    past_course =
      generate(course(name: "Autumn wreaths")) |> Ash.Seed.update!(%{date: Date.add(Edenflowers.ShopTime.today(), -1)})

    generate(
      course_registration(
        course_id: past_course.id,
        status: :confirmed,
        name: "Past Paula",
        confirmed_at: DateTime.utc_now()
      )
    )

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(
             view,
             ~s(#recent-bookings a[href="/admin/courses/#{course.id}?booking=#{booking.id}#registration-#{booking.id}"]),
             "Birgitta"
           )

    assert has_element?(view, "#recent-bookings", "Spring posies")
    refute has_element?(view, "#recent-bookings", "Halfway Hanna")
    refute has_element?(view, "#recent-bookings", "Past Paula")
  end

  test "shows paid sales and revenue for the current month only", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn = log_in(conn, admin)

    now = DateTime.utc_now()
    placed_order(ordered_at: now, paid: "45.00")
    placed_order(ordered_at: now, paid: "45.00")
    placed_order(ordered_at: now, paid: "45.00", refunded: true)
    placed_order(ordered_at: DateTime.add(now, -40, :day), paid: "45.00")

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert view |> element("#sales dd") |> render() =~ ~r/>\s*2\s*</
    assert has_element?(view, "#revenue dd", "90,00 €")
  end

  test "totals the expenses paid this month to today, in each currency", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = log_in(conn, admin)
    today = Edenflowers.ShopTime.today()

    paid_expense(today, "40.00", :eur)
    paid_expense(Date.beginning_of_month(today), "2.50", :eur)
    paid_expense(today, "100.00", :sek)
    # Paid last month, scheduled later, unpaid or in no currency yet: none counts.
    paid_expense(today, "500.00", nil)
    paid_expense(Date.add(Date.beginning_of_month(today), -1), "500.00", :eur)
    paid_expense(Date.add(today, 1), "500.00", :eur)
    paid_expense(nil, "500.00", :eur)

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#expenses-paid", "42,50\u00A0€")
    assert has_element?(view, "#expenses-paid", "SEK")
    refute has_element?(view, "#expenses-paid", "542,50\u00A0€")
    # One line per currency: euros and kronor, no blank one for the expense in no currency.
    assert view |> element("#expenses-paid") |> render() |> then(&Regex.scan(~r/class="block"/, &1)) |> length() == 2
  end

  defp paid_expense(paid_on, amount, currency) do
    Ash.Seed.seed!(Edenflowers.Expenses.Expense, %{
      document_id: "doc-#{System.unique_integer([:positive])}",
      paid_on: paid_on,
      total_amount: Decimal.new(amount),
      currency: currency,
      sure: true,
      processed_at: DateTime.utc_now()
    })
  end

  test "compares with last month up to the same day", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn = log_in(conn, admin)

    same_day = Date.shift(Edenflowers.ShopTime.today(), month: -1)
    noon = fn date -> DateTime.new!(date, ~T[12:00:00], Edenflowers.ShopTime.timezone()) end

    placed_order(ordered_at: noon.(Date.beginning_of_month(same_day)), paid: "30.00")
    placed_order(ordered_at: noon.(same_day), paid: "20.00")
    # Past the matching day, so it doesn't count even when it falls in last month.
    placed_order(ordered_at: noon.(Date.add(same_day, 1)), paid: "45.00")

    {:ok, view, _html} = live(conn, ~p"/admin")

    to = Edenflowers.Format.day_month(same_day, Edenflowers.Format.locale())
    assert has_element?(view, "#last-month", "Last month by #{to}")
    assert has_element?(view, "#sales-last-month", "2")
    assert has_element?(view, "#revenue-last-month", "50,00 €")
    assert has_element?(view, "#revenue-pace", "Last month")
  end

  test "compares Minimossen's latest week with the 8-week average before there's a year to compare with", %{conn: conn} do
    conn = log_in(conn, generate(admin_user()) |> with_token())
    {:ok, view, _html} = live(conn, ~p"/admin")
    refute has_element?(view, "#minimossen")

    record_minimossen([
      {~D[2026-10-26], "3", "120.00"},
      {~D[2026-10-26], "6", "360.00"},
      {~D[2026-11-02], "3", "154.40"},
      {~D[2026-11-02], "6", "406.90"}
    ])

    {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#minimossen dt", "Week 45")
    assert has_element?(view, "#minimossen-total", euros("561.30"))
    assert has_element?(view, "#minimossen-change", "8-week average #{euros("480.00")} +17%")
  end

  test "compares Minimossen's latest week with the same week last year", %{conn: conn} do
    conn = log_in(conn, generate(admin_user()) |> with_token())

    record_minimossen([
      {~D[2025-11-03], "3", "400.00"},
      {~D[2026-10-26], "3", "120.00"},
      {~D[2026-11-02], "3", "500.00"}
    ])

    {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#minimossen-change", "Week 45 last year #{euros("400.00")} +25%")
  end

  defp euros(amount), do: Edenflowers.Format.currency(Decimal.new(amount), Edenflowers.Format.locale())

  defp record_minimossen(sales) do
    for {week_start, code, gross} <- sales do
      Edenflowers.Minimossen.record_minimossen_sales!(
        %{week_start: week_start, group_code: code, group_name: "Group #{code}", gross: gross},
        actor: Edenflowers.Actors.system_actor()
      )
    end
  end
end

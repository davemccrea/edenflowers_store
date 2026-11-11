defmodule EdenflowersWeb.Admin.SubscriptionDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: false
  use Oban.Testing, repo: Edenflowers.Repo

  import Generator
  import Phoenix.LiveViewTest

  setup :log_in_admin

  setup do
    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    %{customer: customer}
  end

  test "an open change drawer preserves input and offers to reload after external changes", %{
    conn: conn,
    customer: customer,
    admin: admin
  } do
    subscription = generate(subscription(user_id: customer.id))
    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    view |> element("button[phx-click=open_change]") |> render_click()
    view |> form("#change-subscription-form", change: %{interval_weeks: 4}) |> render_change()

    Edenflowers.Orders.pause_subscription!(subscription, actor: admin)

    assert has_element?(view, "#subscription-status", "Active")
    assert has_element?(view, "#change-subscription-form option[value='4'][selected]")
    assert has_element?(view, "#change-subscription-stale-notice[role=alert]")
    assert has_element?(view, "#editor-stale-notice")

    view |> element("#editor-stale-notice button") |> render_click()
    {path, _} = assert_redirect(view)
    {:ok, view, _html} = live(conn, path)
    refute has_element?(view, "#editor-stale-notice")
    refute has_element?(view, "#change-subscription-form")
    assert has_element?(view, "#subscription-status", "Paused")
  end

  test "a refused subscription change keeps its errors through notifications", %{conn: conn, admin: admin} do
    subscription = generate(subscription())
    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    view |> element("button[phx-click=open_change]") |> render_click()
    render_submit(view, "change", %{"change" => %{"interval_weeks" => "3"}})
    assert has_element?(view, "#change-subscription-form [aria-invalid=true]")

    Edenflowers.Orders.pause_subscription!(subscription, actor: admin)

    assert has_element?(view, "#change-subscription-form [aria-invalid=true]")
    assert has_element?(view, "#editor-stale-notice")
    render_click(view, "close_change")
    assert has_element?(view, "#editor-stale-notice")
    refute has_element?(view, "#change-subscription-form")
  end

  test "a cancellation drawer keeps its email draft until closed", %{conn: conn, admin: admin} do
    subscription = generate(subscription())
    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    view |> element("button[phx-click=open_cancel]") |> render_click()
    view |> form("#cancel-subscription-form", cancel: %{edit_email: "true"}) |> render_change()
    view |> form("#cancel-subscription-form", cancel: %{body: "Keep my wording"}) |> render_change()

    Edenflowers.Orders.pause_subscription!(subscription, actor: admin)

    assert has_element?(view, "#cancel-subscription-form textarea", "Keep my wording")
    assert has_element?(view, "#cancel-subscription-stale-notice[role=alert]")
    assert has_element?(view, "#editor-stale-notice")
    render_click(view, "close_cancel")
    assert has_element?(view, "#editor-stale-notice")
    refute has_element?(view, "#cancel-subscription-form")
    assert has_element?(view, "#subscription-status", "Active")
  end

  test "names the weekday it delivers on, even while paused", %{conn: conn, customer: customer} do
    friday =
      Enum.find(Date.range(Date.add(Date.utc_today(), 7), Date.add(Date.utc_today(), 13)), &(Date.day_of_week(&1) == 5))

    subscription = generate(subscription(user_id: customer.id, state: :paused, next_fulfillment_date: friday))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")

    assert has_element?(view, "#subscription-fulfillment", "Delivery day")
    assert has_element?(view, "#subscription-delivery-day", "Friday")
  end

  test "collection notifications do not mix other subscriptions' orders into the page", %{
    conn: conn,
    customer: customer,
    admin: admin
  } do
    subscription = generate(subscription(user_id: customer.id))
    other = generate(subscription())
    order = placed_order(subscription_id: other.id, payment_intent_id: nil)
    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    render_async(view)

    {:ok, _other} = Edenflowers.Orders.pause_subscription(other, actor: admin)
    {:ok, _order} = Edenflowers.Orders.record_payment(order, "10.00", :cash, actor: admin)
    render_async(view)

    assert has_element?(view, "#subscription-status", "Active")
    refute has_element?(view, ~s|[data-item-id="#{order.id}"]|)
  end

  test "external subscription changes only appear after reload, local actions reload immediately", %{
    conn: conn,
    customer: customer,
    admin: admin
  } do
    subscription = generate(subscription(user_id: customer.id))
    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    render_async(view)

    {:ok, _subscription} = Edenflowers.Orders.pause_subscription(subscription, actor: admin)

    assert has_element?(view, "#editor-stale-notice")
    assert has_element?(view, "#subscription-status", "Active")
    view |> element("#editor-stale-notice button") |> render_click()
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#subscription-status", "Paused")
    view |> element("button", "Resume") |> render_click()
    render_async(view)

    assert has_element?(view, "#subscription-status", "Active")
  end

  test "related orders only change after reload and stay scoped to their subscription", %{
    conn: conn,
    customer: customer,
    admin: admin
  } do
    first = generate(subscription(user_id: customer.id))
    second = generate(subscription(user_id: customer.id))
    {:ok, first_view, _html} = live(conn, ~p"/admin/subscriptions/#{first.id}")
    {:ok, second_view, _html} = live(conn, ~p"/admin/subscriptions/#{second.id}")
    render_async(first_view)
    render_async(second_view)

    # Seeding an order does not broadcast a notification. The real subscription
    # job creates an order and then places it through an action that broadcasts.
    # The payment action below supplies a broadcast for this seeded order.
    order = placed_order(subscription_id: first.id, payment_intent_id: nil)
    refute has_element?(first_view, ~s|[data-item-id="#{order.id}"]|)

    {:ok, _order} = Edenflowers.Orders.record_payment(order, "10.00", :cash, actor: admin)
    assert has_element?(first_view, "#editor-stale-notice")
    refute has_element?(first_view, ~s|[data-item-id="#{order.id}"]|)
    refute has_element?(second_view, ~s|[data-item-id="#{order.id}"]|)
    {:ok, first_view, _} = live(conn, ~p"/admin/subscriptions/#{first.id}")
    {:ok, second_view, _} = live(conn, ~p"/admin/subscriptions/#{second.id}")
    assert has_element?(first_view, ~s|[data-item-id="#{order.id}"]|)
    refute has_element?(second_view, ~s|[data-item-id="#{order.id}"]|)
  end

  test "closed-day warnings only change after explicit reload", %{
    conn: conn,
    customer: customer,
    admin: admin
  } do
    date = Date.add(Edenflowers.ShopTime.today(), 7)
    subscription = generate(subscription(user_id: customer.id, next_fulfillment_date: date))
    calendar = shop_calendar(disabled_dates: [], enabled_dates: [])
    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    refute has_element?(view, "#subscription-closed-days")
    render_async(view)

    calendar = Edenflowers.Fulfillment.toggle_date!(calendar, date, actor: admin)

    assert has_element?(view, "#editor-stale-notice")
    refute has_element?(view, "#subscription-closed-days")
    {:ok, view, _} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    assert has_element?(view, "#subscription-closed-days")

    Edenflowers.Fulfillment.toggle_date!(calendar, date, actor: admin)

    assert has_element?(view, "#editor-stale-notice")
    assert has_element?(view, "#subscription-closed-days")
    {:ok, view, _} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    refute has_element?(view, "#subscription-closed-days")
  end

  test "shows what Jennie needs to service the subscription", %{conn: conn, customer: customer} do
    large = generate(product_variant(product_id: generate(product()).id, size: :large))

    subscription =
      generate(
        subscription(
          user_id: customer.id,
          product_variant_id: large.id,
          recipient_name: "Grace Hopper",
          delivery_address: "Storgatan 1, Jakobstad",
          delivery_instructions: "Ring the bell twice",
          card_message: "Happy Mondays",
          card_brand: "visa",
          card_last4: "4242",
          card_exp_month: 8,
          card_exp_year: 2027
        )
      )

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")

    assert has_element?(view, "h1", "Ada Lovelace")
    assert has_element?(view, "#subscription-customer", "ada@example.com")
    assert has_element?(view, "#subscription-customer-link[href='/admin/customers/#{customer.id}']")
    assert render(view) =~ "Large"
    assert render(view) =~ "Every 2 weeks"
    assert has_element?(view, "#subscription-fulfillment", "Storgatan 1, Jakobstad")
    assert has_element?(view, "#subscription-fulfillment", "Ring the bell twice")
    refute render(view) =~ "Happy Mondays"
    assert has_element?(view, "#subscription-recipient", "Grace Hopper")
    assert has_element?(view, ~s|#subscription-card img[alt="Visa"]|)
    assert has_element?(view, "#subscription-card", "•••• 4242, expires 08/27")
  end

  test "Jennie can pause, resume and cancel, even inside the customer's cutoff", %{conn: conn, customer: customer} do
    next_date = Edenflowers.ShopTime.today() |> Date.add(4)
    subscription = generate(subscription(user_id: customer.id, next_fulfillment_date: next_date))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")

    view |> element("button", "Pause") |> render_click()
    assert reload(subscription).state == :paused

    view |> element("button", "Resume") |> render_click()
    assert reload(subscription).state == :active

    view |> element(~s|button[phx-click="open_cancel"]|) |> render_click()
    assert has_element?(view, "#cancel-subscription-email-send[checked]")
    view |> form("#cancel-subscription-form", cancel: %{edit_email: "true"}) |> render_change()

    view
    |> form("#cancel-subscription-form", cancel: %{edit_email: "true", body: "Thank you for a lovely year."})
    |> render_submit()

    assert reload(subscription).state == :cancelled
    refute has_element?(view, ~s|button[phx-click="open_cancel"]|)

    assert_enqueued(
      worker: Edenflowers.Orders.Workers.SendSubscriptionCancelledEmail,
      args: %{
        "primary_key" => %{"id" => subscription.id},
        "action_arguments" => %{"body" => "Thank you for a lovely year."}
      }
    )
  end

  test "Jennie can change the size and how often, even inside the customer's cutoff", %{
    conn: conn,
    customer: customer
  } do
    product = generate(product())
    medium = generate(product_variant(product_id: product.id, size: :medium, draft: false))
    large = generate(product_variant(product_id: product.id, size: :large, draft: false))
    next_date = Edenflowers.ShopTime.today() |> Date.add(2)

    subscription =
      generate(subscription(user_id: customer.id, product_variant_id: medium.id, next_fulfillment_date: next_date))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")

    view |> element(~s|button[phx-click="open_change"]|) |> render_click()

    view
    |> form("#change-subscription-form", change: %{product_variant_id: large.id, interval_weeks: 4})
    |> render_submit()

    changed = reload(subscription)
    assert changed.product_variant_id == large.id
    assert changed.interval_weeks == 4
    assert has_element?(view, "#subscription-log", "Changed · Admin")
    refute has_element?(view, "#editor-stale-notice")
  end

  test "names a delivery on a closed day, and prices each size per delivery", %{conn: conn, customer: customer} do
    delivery = generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :dynamic, base_price: "4.50"))
    product = generate(product(free_delivery: false))
    medium = generate(product_variant(product_id: product.id, size: :medium, price: "60.00", draft: false))
    large = generate(product_variant(product_id: product.id, size: :large, price: "80.00", draft: false))
    closed = Edenflowers.ShopTime.today() |> Date.add(5)

    subscription =
      generate(
        subscription(
          user_id: customer.id,
          product_variant_id: medium.id,
          fulfillment_option_id: delivery.id,
          next_fulfillment_date: closed
        )
      )

    generate(order(subscription_id: subscription.id, origin: :online, state: :placed, distance: 3000))
    shop_calendar(disabled_dates: [closed])

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")

    assert has_element?(
             view,
             "#subscription-closed-days",
             "You've closed #{Edenflowers.Format.weekday_day_month(closed, "en-GB")}"
           )

    view |> element(~s|button[phx-click="open_change"]|) |> render_click()
    fee = Ash.load!(subscription, :fee_per_order, authorize?: false).fee_per_order
    assert Decimal.positive?(fee)

    assert has_element?(
             view,
             ~s|#change-subscription option[value="#{large.id}"]|,
             Edenflowers.Format.currency(Decimal.add(large.price, fee), "en-GB")
           )
  end

  test "cancelling with the email unticked sends nothing", %{conn: conn, customer: customer} do
    subscription = generate(subscription(user_id: customer.id))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    view |> element(~s|button[phx-click="open_cancel"]|) |> render_click()
    view |> form("#cancel-subscription-form", cancel: %{email_customer?: "false"}) |> render_submit()

    assert reload(subscription).state == :cancelled
    refute_enqueued(worker: Edenflowers.Orders.Workers.SendSubscriptionCancelledEmail)
  end

  test "logs who changed the subscription, naming no one for automatic changes", %{conn: conn, customer: customer} do
    product = generate(product())
    medium = generate(product_variant(product_id: product.id, size: :medium, draft: false))
    large = generate(product_variant(product_id: product.id, size: :large, draft: false))

    subscription =
      generate(subscription(user_id: customer.id, product_variant_id: medium.id, state: :payment_failed))

    {:ok, subscription} =
      Edenflowers.Orders.reactivate_subscription(subscription, actor: Edenflowers.Actors.system_actor())

    {:ok, _subscription} =
      Edenflowers.Orders.change_subscription(subscription, %{product_variant_id: large.id}, actor: customer)

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    view |> element("button", "Pause") |> render_click()

    [paused, changed, restarted] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#subscription-history > li:not([role=presentation])")
      |> Enum.map(&LazyHTML.text/1)

    assert paused =~ "Paused · Admin"
    assert changed =~ "Changed · Ada Lovelace"
    assert changed =~ "Large"
    assert restarted =~ "Payment received, deliveries restarted"
    refute restarted =~ "·"
  end

  defp reload(subscription), do: Ash.reload!(subscription, authorize?: false)
end

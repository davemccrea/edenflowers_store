defmodule EdenflowersWeb.Account.AccountLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  use Oban.Testing, repo: Edenflowers.Repo

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Accounts.Workers.SendEmailChangeCode
  alias EdenflowersWeb.Account.AccountLive

  @locale "en-GB"

  setup %{conn: conn} do
    user = generate(admin_user(admin: false, name: "Ada Lovelace")) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(user)

    %{conn: conn, user: user}
  end

  describe "details" do
    test "greets the customer by first name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "h1", "Hi, Ada")
    end

    test "changes the customer's name", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account")

      view
      |> form("#details-form", %{"details" => %{"name" => "Grace Hopper", "email" => to_string(user.email)}})
      |> render_submit()

      assert has_element?(view, "h1", "Hi, Grace")
      assert Ash.get!(Edenflowers.Accounts.User, user.id, authorize?: false).name == "Grace Hopper"
    end

    test "changes the email only once the code sent to it is entered", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account")

      view
      |> form("#details-form", %{"details" => %{"name" => "Ada Lovelace", "email" => "new@example.com"}})
      |> render_submit()

      [job] = all_enqueued(worker: SendEmailChangeCode)
      assert %{"email" => "new@example.com", "code" => code} = job.args
      refute to_string(Ash.get!(Edenflowers.Accounts.User, user.id, authorize?: false).email) == "new@example.com"

      view |> form("#email-code-form", %{"confirm" => %{"code" => "000000"}}) |> render_submit()
      assert has_element?(view, "#email-code-form", "That code isn't right.")

      view |> form("#email-code-form", %{"confirm" => %{"code" => code}}) |> render_submit()

      assert to_string(Ash.get!(Edenflowers.Accounts.User, user.id, authorize?: false).email) == "new@example.com"
      assert has_element?(view, "#details-form")
    end

    test "gives up on the email change after too many wrong codes", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account")

      view
      |> form("#details-form", %{"details" => %{"name" => "Ada Lovelace", "email" => "new@example.com"}})
      |> render_submit()

      for _ <- 1..5 do
        view |> form("#email-code-form", %{"confirm" => %{"code" => "wrong"}}) |> render_submit()
      end

      assert has_element?(view, "#details-form", "Too many wrong codes.")
      refute to_string(Ash.get!(Edenflowers.Accounts.User, user.id, authorize?: false).email) == "new@example.com"
    end
  end

  describe "orders" do
    test "lists the customer's own orders with a receipt link", %{conn: conn, user: user} do
      order = placed_order(user_id: user.id)

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "[data-testid=orders-table]", order.order_reference)
      assert has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|, "Receipt")
    end

    test "hides the receipt link for an order that isn't paid", %{conn: conn, user: user} do
      order = placed_order(user_id: user.id, payment_status: :refunded)

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "[data-testid=orders-table]", "Refunded")
      refute has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)
    end

    test "offers to pay an unpaid custom order through its payment link", %{conn: conn, user: user} do
      order = placed_order(user_id: user.id, origin: :custom, payment_status: :pending, payment_link_token: "tok123")

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, ~s|[data-testid=order-unpaid] a[href="/pay/tok123"]|, "Pay now")
      refute has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)
    end

    test "tells a customer paying in person when to pay", %{conn: conn, user: user} do
      placed_order(user_id: user.id, origin: :custom, payment_status: :pending)

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "[data-testid=order-unpaid]", "Pay at collection")
    end

    test "shows a cancelled order as cancelled", %{conn: conn, user: user} do
      placed_order(user_id: user.id, origin: :custom, payment_status: :pending, fulfillment_status: :cancelled)

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "[data-testid=orders-table]", "Cancelled")
      refute has_element?(view, "[data-testid=order-unpaid]")
    end

    test "does not list another customer's orders", %{conn: conn} do
      other = generate(admin_user(admin: false))
      order = placed_order(user_id: other.id)

      {:ok, view, _html} = live(conn, ~p"/account")

      refute has_element?(view, "[data-testid=orders-table]")
      refute render(view) =~ order.order_reference
    end

    test "does not list another customer's orders to an admin", %{conn: conn} do
      # Order's read policy has a bypass granting admins an unrestricted read,
      # so only the action's own filter keeps Jennie's account page to her orders.
      admin = generate(admin_user(admin: true)) |> with_token()
      other = generate(admin_user(admin: false))
      order = placed_order(user_id: other.id)

      conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

      {:ok, view, _html} = live(conn, ~p"/account")

      refute render(view) =~ order.order_reference
    end

    test "points a customer with no orders at the shop", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "#orders-heading")
      assert has_element?(view, ~s|a[href="/store"]|, "Visit the shop")
    end
  end

  describe "status_label/2" do
    test "names the outcome once an order is fulfilled" do
      assert AccountLive.status_label(order_for(fulfillment_status: :fulfilled), @locale) =~ "Delivered"

      assert AccountLive.status_label(
               order_for(fulfillment_status: :fulfilled, fulfillment_method: :pickup),
               @locale
             ) =~ "Collected"
    end

    test "looks forward to a fulfillment date still to come" do
      order = order_for(fulfillment_date: Date.add(store_today(), 3))

      assert AccountLive.status_label(order, @locale) =~ "Arriving"
      assert AccountLive.status_label(%{order | fulfillment_method: :pickup}, @locale) =~ "Ready to collect"
    end

    test "says today without a date when the order lands today" do
      order = order_for(fulfillment_date: store_today())

      assert AccountLive.status_label(order, @locale) == "Arriving today"
      assert AccountLive.status_label(%{order | fulfillment_method: :pickup}, @locale) == "Ready to collect today"
    end

    test "never claims delivery for a past date Jennie hasn't marked fulfilled" do
      order = order_for(fulfillment_date: Date.add(store_today(), -3))

      label = AccountLive.status_label(order, @locale)

      assert label =~ "Delivery on"
      refute label =~ "Delivered"
    end

    test "reports a refund ahead of anything else" do
      order = order_for(payment_status: :refunded, fulfillment_status: :fulfilled)

      assert AccountLive.status_label(order, @locale) == "Refunded"
    end

    test "falls back to Confirmed when there is no fulfillment date" do
      assert AccountLive.status_label(order_for(fulfillment_date: nil), @locale) == "Confirmed"
    end
  end

  describe "courses" do
    test "lists the customer's own registrations", %{conn: conn, user: user} do
      course = generate(course(name: "Autumn Wreaths"))

      registration =
        generate(course_registration(course_id: course.id, user_id: user.id, status: :confirmed, seats: 2))

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, ~s|[data-testid=courses-table] a[href="/courses/#{course.id}"]|, "Autumn Wreaths")
      assert has_element?(view, "[data-testid=courses-table] td", "2")
      assert has_element?(view, ~s|a[href="/courses/bookings/#{registration.id}/receipt"]|, "Receipt")
    end

    @tag :typst
    test "opens a booking's receipt PDF inline", %{conn: conn, user: user} do
      registration = generate(course_registration(user_id: user.id, status: :confirmed))

      conn = get(conn, ~p"/courses/bookings/#{registration.id}/receipt")

      assert "%PDF" <> _ = response(conn, 200)

      assert get_resp_header(conn, "content-disposition") == [
               ~s|inline; filename="eden-flowers-#{registration.reference}.pdf"|
             ]
    end

    test "hides another customer's booking receipt", %{conn: conn} do
      other = generate(admin_user(admin: false))
      registration = generate(course_registration(user_id: other.id, status: :confirmed))

      assert conn |> get(~p"/courses/bookings/#{registration.id}/receipt") |> response(404)
    end

    test "does not list a booking that hasn't been paid for", %{conn: conn, user: user} do
      course = generate(course(name: "Spring Posies"))
      generate(course_registration(course_id: course.id, user_id: user.id, status: :pending))

      {:ok, view, _html} = live(conn, ~p"/account")

      refute render(view) =~ "Spring Posies"
    end

    test "does not list a guest registration made with the same email", %{conn: conn, user: user} do
      course = generate(course(name: "Winter Bouquets"))
      generate(course_registration(course_id: course.id, user_id: nil, email: to_string(user.email)))

      {:ok, view, _html} = live(conn, ~p"/account")

      refute render(view) =~ "Winter Bouquets"
    end

    test "does not list another customer's registration to an admin", %{conn: conn} do
      admin = generate(admin_user(admin: true)) |> with_token()
      other = generate(admin_user(admin: false))
      course = generate(course(name: "Midsummer Garlands"))
      generate(course_registration(course_id: course.id, user_id: other.id, status: :confirmed))

      conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

      {:ok, view, _html} = live(conn, ~p"/account")

      refute render(view) =~ "Midsummer Garlands"
    end

    test "points a customer with no registrations at the courses page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, ~s|a[href="/courses"]|, "See what's coming up")
    end
  end

  describe "subscriptions" do
    defp subscription(user, attrs) do
      Ash.Seed.seed!(
        Edenflowers.Orders.Subscription,
        Map.merge(
          %{
            user_id: user.id,
            product_variant_id: generate(product_variant(product_id: generate(product()).id, size: :medium)).id,
            fulfillment_option_id: generate(fulfillment_option(fulfillment_method: :delivery)).id,
            interval_weeks: 2,
            next_fulfillment_date: days_from_today(14),
            locale: "en",
            stripe_customer_id: "cus_ada",
            stripe_payment_method_id: "pm_card"
          },
          attrs
        )
      )
    end

    defp days_from_today(days), do: Date.add(Edenflowers.Expressions.HelsinkiToday.today(), days)

    defp weekday_date(date), do: Edenflowers.Format.weekday_date(date, @locale)

    defp reload(subscription), do: Ash.reload!(subscription, authorize?: false)

    defp row(subscription), do: "#subscription-#{subscription.id}"
    defp drawer(subscription), do: "#manage-subscription-#{subscription.id}"

    test "lists the customer's subscriptions, not anyone else's", %{conn: conn, user: user} do
      mine = subscription(user, %{})
      theirs = subscription(generate(admin_user(admin: false)), %{})

      {:ok, view, _html} = live(conn, ~p"/account")

      variant = Ash.load!(mine, product_variant: :product).product_variant
      next = mine.next_fulfillment_date

      assert has_element?(view, "#{row(mine)} th", variant.product.name)
      assert has_element?(view, "#{row(mine)} th", "Medium · Every 2 weeks")
      assert has_element?(view, row(mine), Edenflowers.Format.currency(variant.price, @locale))

      assert has_element?(
               view,
               "#{row(mine)} [data-testid=subscription-status]",
               Edenflowers.Format.weekday_day_month(next, @locale)
             )

      assert has_element?(
               view,
               "#{row(mine)} [data-testid=subscription-status]",
               "Charged #{Edenflowers.Format.day_month(Date.add(next, -3), @locale)}"
             )

      assert has_element?(
               view,
               "#{drawer(mine)} [data-testid=subscription-drawer-status]",
               "Charged to your card on #{weekday_date(Date.add(next, -3))}."
             )

      refute has_element?(view, row(theirs))
      refute has_element?(view, drawer(theirs))
    end

    test "shows a delivery that's already booked as the next one", %{conn: conn, user: user} do
      subscription = subscription(user, %{next_fulfillment_date: days_from_today(30)})
      placed_order(user_id: user.id, subscription_id: subscription.id, fulfillment_date: days_from_today(2))
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(
               view,
               "#{row(subscription)} [data-testid=subscription-status]",
               Edenflowers.Format.weekday_day_month(days_from_today(2), @locale)
             )

      assert has_element?(
               view,
               "#{drawer(subscription)} [data-testid=subscription-drawer-status]",
               "The one after: #{weekday_date(days_from_today(30))}"
             )
    end

    test "lists cancelled subscriptions last, and drops them after a month", %{conn: conn, user: user} do
      cancelled = subscription(user, %{state: :cancelled})
      active = subscription(user, %{})
      long_gone = subscription(user, %{state: :cancelled, updated_at: DateTime.add(DateTime.utc_now(), -31, :day)})
      {:ok, _view, html} = live(conn, ~p"/account")

      ids = Regex.scan(~r/<tr[^>]* id="subscription-([0-9a-f-]{36})"/, html, capture: :all_but_first) |> List.flatten()
      assert ids == [active.id, cancelled.id]
      assert html =~ "Cancelled on #{weekday_date(Edenflowers.Expressions.HelsinkiToday.today())}."
      refute html =~ long_gone.id
    end

    test "points to the subscription product without a subscription", %{conn: conn} do
      category = generate(product_category(visibility: :public))

      product =
        generate(product(subscribable: true, free_delivery: true, draft: false, product_category_id: category.id))

      generate(product_variant(product_id: product.id))
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, ~s|[data-testid=no-subscriptions] a[href="/product/#{product.id}"]|)
    end

    test "shows who a subscription delivers to, and offers a fresh start once cancelled", %{conn: conn, user: user} do
      gift = subscription(user, %{recipient_name: "Ingrid Nyman", delivery_address: "Gerbyntie 16, Vaasa"})
      cancelled = subscription(user, %{state: :cancelled})
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "#{drawer(gift)} [data-testid=subscription-recipient]", "Ingrid Nyman")
      assert has_element?(view, "#{drawer(gift)} [data-testid=subscription-recipient]", "Gerbyntie 16, Vaasa")

      variant = Ash.get!(Edenflowers.Catalog.ProductVariant, cancelled.product_variant_id)

      assert has_element?(
               view,
               ~s|#{drawer(cancelled)} a[href="/product/#{variant.product_id}"]|,
               "Start a new subscription"
             )
    end

    test "marks subscription deliveries in the orders", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      placed_order(user_id: user.id, subscription_id: subscription.id)
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "[data-testid=orders-table] [data-testid=order-subscription]", "Subscription")
    end

    test "pauses and resumes", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      {:ok, view, _html} = live(conn, ~p"/account")

      view |> element("#subscription-#{subscription.id}-pause", "Pause") |> render_click()
      assert reload(subscription).state == :paused
      assert has_element?(view, "#{row(subscription)} [data-testid=subscription-status]", "No deliveries or charges")

      assert has_element?(
               view,
               "#{drawer(subscription)} [data-testid=subscription-drawer-status]",
               "Resume now and your next delivery is #{weekday_date(subscription.next_fulfillment_date)}."
             )

      view |> element("#subscription-#{subscription.id}-pause", "Resume") |> render_click()
      assert reload(subscription).state == :active
    end

    test "cancels", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "#cancel-subscription-#{subscription.id}", "Want a break instead?")
      view |> element("#cancel-subscription-#{subscription.id} button", "Stop subscription") |> render_click()

      assert reload(subscription).state == :cancelled
      assert has_element?(view, "#{row(subscription)} [data-testid=subscription-status]", "Cancelled")
      refute has_element?(view, "#cancel-subscription-#{subscription.id}")
      refute has_element?(view, "#change-subscription-#{subscription.id}")
    end

    test "shows the final booked delivery when cancelling after its deadline", %{conn: conn, user: user} do
      subscription = subscription(user, %{})

      occurrence =
        placed_order(
          user_id: user.id,
          origin: :subscription,
          subscription_id: subscription.id,
          subscription_date: days_from_today(4),
          fulfillment_date: days_from_today(4)
        )

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "#cancel-subscription-#{subscription.id} [data-testid=final-delivery-warning]")
      view |> element("#cancel-subscription-#{subscription.id} button", "Stop subscription") |> render_click()

      assert reload(subscription).state == :cancelled
      assert Ash.reload!(occurrence, authorize?: false).fulfillment_status == :pending
      assert has_element?(view, "#{row(subscription)} [data-testid=subscription-status]", "One final delivery remains")

      assert has_element?(
               view,
               "#{drawer(subscription)} [data-testid=subscription-drawer-status]",
               "One final delivery remains"
             )
    end

    test "pauses from the cancel dialog instead", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      {:ok, view, _html} = live(conn, ~p"/account")

      view |> element("#cancel-subscription-#{subscription.id} button", "Pause it") |> render_click()

      assert reload(subscription).state == :paused
    end

    test "offers only cancellation inside the cutoff", %{conn: conn, user: user} do
      subscription = subscription(user, %{next_fulfillment_date: days_from_today(4)})
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(
               view,
               "#{drawer(subscription)} [data-testid=changes-closed]",
               "You can make changes again from #{weekday_date(days_from_today(1))}."
             )

      assert has_element?(view, ~s|#{drawer(subscription)} [data-testid=changes-closed] a[href="/contact"]|)
      refute has_element?(view, "#subscription-#{subscription.id}-pause")
      refute has_element?(view, "#change-subscription-#{subscription.id}")
      assert has_element?(view, "#cancel-subscription-#{subscription.id}")
    end

    test "asks a held subscription for a new card and the unpaid delivery", %{conn: conn, user: user} do
      subscription = subscription(user, %{state: :payment_failed})

      unpaid =
        placed_order(
          user_id: user.id,
          subscription_id: subscription.id,
          payment_status: :pending,
          payment_link_token: "tok_held"
        )

      {:ok, view, _html} = live(conn, ~p"/account")

      date = weekday_date(unpaid.fulfillment_date)

      assert has_element?(view, "#{row(subscription)} [data-testid=subscription-status]", "Payment failed")
      assert has_element?(view, ~s|#{row(subscription)} [data-testid=subscription-pay-now][href="/pay/tok_held"]|)

      assert has_element?(
               view,
               "#{drawer(subscription)} [data-testid=subscription-payment]",
               "We couldn't charge your card for #{date}"
             )

      assert has_element?(
               view,
               ~s|#{drawer(subscription)} [data-testid=subscription-update-card][href="/account/subscriptions/#{subscription.id}/card"]|
             )

      refute has_element?(view, "#change-subscription-#{subscription.id}")
    end

    test "keeps asking for an unpaid delivery once the new card has restarted the subscription", %{
      conn: conn,
      user: user
    } do
      subscription = subscription(user, %{})

      placed_order(
        user_id: user.id,
        subscription_id: subscription.id,
        payment_status: :pending,
        payment_link_token: "tok_held"
      )

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "#{row(subscription)} [data-testid=subscription-status]", "Unpaid")
      assert has_element?(view, "#{drawer(subscription)} [data-testid=subscription-payment]", "is still unpaid")
      assert has_element?(view, ~s|#{drawer(subscription)} [data-testid=subscription-pay-now][href="/pay/tok_held"]|)
      refute has_element?(view, "#{drawer(subscription)} [data-testid=subscription-update-card]")
    end

    test "changes the size and how often", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      variant = Ash.get!(Edenflowers.Catalog.ProductVariant, subscription.product_variant_id)
      large = generate(product_variant(product_id: variant.product_id, size: :large, draft: false))
      {:ok, view, _html} = live(conn, ~p"/account")

      save = "#change-subscription-#{subscription.id} button[type=submit]"
      assert has_element?(view, "#{save}[disabled]")

      changes = %{"product_variant_id" => large.id, "interval_weeks" => "4"}
      view |> form("#change-subscription-#{subscription.id}", changes) |> render_change()
      refute has_element?(view, "#{save}[disabled]")

      view |> form("#change-subscription-#{subscription.id}", changes) |> render_submit()

      assert %{product_variant_id: large_id, interval_weeks: 4} = reload(subscription)
      assert large_id == large.id
      assert has_element?(view, "#{row(subscription)} th", "Large · Every 4 weeks")

      price = Edenflowers.Format.storefront_price(large.price, @locale)

      assert render(view) =~
               "From #{weekday_date(reload(subscription).next_fulfillment_date)}: Large, every 4 weeks, #{price} per delivery."
    end

    test "moves deliveries to another day", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      next = subscription.next_fulfillment_date
      day = Edenflowers.Fulfillment.Weekday.from_date(Date.add(next, 1))
      {:ok, view, _html} = live(conn, ~p"/account")

      changes = %{
        "product_variant_id" => subscription.product_variant_id,
        "interval_weeks" => "2",
        "delivery_day" => day
      }

      view |> form("#change-subscription-#{subscription.id}", changes) |> render_change()
      view |> form("#change-subscription-#{subscription.id}", changes) |> render_submit()

      assert reload(subscription).next_fulfillment_date == Date.add(next, 1)
      assert render(view) =~ "From #{weekday_date(Date.add(next, 1))}:"
    end

    test "shows the card deliveries are charged to", %{conn: conn, user: user} do
      subscription =
        subscription(user, %{card_brand: "visa", card_last4: "4242", card_exp_month: 8, card_exp_year: 2027})

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(
               view,
               "#{drawer(subscription)} [data-testid=subscription-card]",
               "Visa •••• 4242, expires 08/27"
             )
    end

    test "links to updating the card, even inside the cutoff", %{conn: conn, user: user} do
      subscription = subscription(user, %{next_fulfillment_date: days_from_today(4)})
      {:ok, view, _html} = live(conn, ~p"/account")

      refute has_element?(view, "#change-subscription-#{subscription.id}")
      assert has_element?(view, ~s|a[href="/account/subscriptions/#{subscription.id}/card"]|, "Update card")
    end

    test "refuses a change to a subscription that isn't the customer's", %{conn: conn, user: user} do
      subscription(user, %{})
      theirs = subscription(generate(admin_user(admin: false)), %{})
      {:ok, view, _html} = live(conn, ~p"/account")

      render_click(view, "pause_subscription", %{"id" => theirs.id})

      assert reload(theirs).state == :active
      assert render(view) =~ "Your subscription couldn&#39;t be changed."
    end

    test "says why a change is refused once the cutoff passes with the page open", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      {:ok, view, _html} = live(conn, ~p"/account")

      Ash.Seed.update!(subscription, %{next_fulfillment_date: days_from_today(4)})
      view |> element("#subscription-#{subscription.id}-pause", "Pause") |> render_click()

      assert reload(subscription).state == :active
      assert render(view) =~ "It&#39;s too late to change your next delivery."
    end
  end

  describe "newsletter" do
    test "saves the preference as soon as the box is ticked", %{conn: conn, user: user} do
      refute user.newsletter_opt_in

      {:ok, view, _html} = live(conn, ~p"/account")

      view
      |> form("#newsletter-preference", %{"newsletter_opt_in" => "true"})
      |> render_change()

      assert has_element?(view, "[role=status]", "Saved")
      assert Ash.get!(Edenflowers.Accounts.User, user.id, authorize?: false).newsletter_opt_in
    end

    test "a superseded timer leaves a fresh confirmation up", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/account")

      view
      |> form("#newsletter-preference", %{"newsletter_opt_in" => "true"})
      |> render_change()

      send(view.pid, {:clear_newsletter_saved, :from_an_earlier_toggle})

      assert has_element?(view, "[role=status]", "Saved")
    end

    test "unticking opts the customer back out", %{conn: conn, user: user} do
      Edenflowers.Accounts.update_newsletter_preference!(user, true, actor: user)

      {:ok, view, _html} = live(conn, ~p"/account")

      view
      |> form("#newsletter-preference", %{"newsletter_opt_in" => "false"})
      |> render_change()

      refute Ash.get!(Edenflowers.Accounts.User, user.id, authorize?: false).newsletter_opt_in
    end
  end

  test "names the page in the browser tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/account")

    assert page_title(view) =~ "Account"
  end

  test "sends a signed-out visitor to sign in" do
    conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/account")
    assert to =~ "/sign-in"
  end

  defp order_for(overrides) do
    defaults = %{
      payment_status: :paid,
      fulfillment_status: :pending,
      fulfillment_method: :delivery,
      fulfillment_date: ~D[2026-06-10]
    }

    Map.merge(defaults, Map.new(overrides))
  end

  defp store_today, do: "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date()

  defp placed_order(overrides) do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "42.00"))
    fulfillment = generate(fulfillment_option(tax_rate_id: tax_rate.id, name: "Pickup"))

    attrs =
      Keyword.merge(
        [
          state: :placed,
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_option_id: fulfillment.id,
          fulfillment_option_name: "Pickup",
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          quoted_fulfillment_fee: "4.50",
          fulfillment_tax_rate: tax_rate.percentage,
          payment_status: :paid,
          ordered_at: DateTime.utc_now(),
          locale: "en-GB"
        ],
        overrides
      )

    {payment_status, attrs} = Keyword.pop(attrs, :payment_status, :pending)
    order = generate(order(attrs))
    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))
    order = Ash.load!(order, :grand_total, authorize?: false)

    if payment_status in [:paid, :refunded],
      do: generate(payment(order_id: order.id, amount: order.grand_total))

    if payment_status == :refunded,
      do: generate(payment(order_id: order.id, amount: Decimal.negate(order.grand_total)))

    Ash.load!(order, :payment_status, authorize?: false, reuse_values?: false)
  end
end

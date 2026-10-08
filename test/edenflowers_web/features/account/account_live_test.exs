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

    defp reload(subscription), do: Ash.reload!(subscription, authorize?: false)

    test "lists the customer's subscriptions, not anyone else's", %{conn: conn, user: user} do
      mine = subscription(user, %{})
      theirs = subscription(generate(admin_user(admin: false)), %{})

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "#subscription-#{mine.id}", "Medium · Every 2 weeks")

      assert has_element?(
               view,
               "#subscription-#{mine.id}",
               "Next delivery #{Edenflowers.Format.date(mine.next_fulfillment_date, @locale)}"
             )

      refute has_element?(view, "#subscription-#{theirs.id}")
    end

    test "hides the section without a subscription", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/account")

      refute has_element?(view, "#subscriptions-heading")
    end

    test "skips the next delivery", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      {:ok, view, _html} = live(conn, ~p"/account")

      view |> element("#subscription-#{subscription.id} button", "Skip next delivery") |> render_click()

      assert reload(subscription).skipped_dates == [subscription.next_fulfillment_date]
      assert has_element?(view, "#subscription-#{subscription.id} [data-testid=subscription-status]", "Skipping")
      refute has_element?(view, "#subscription-#{subscription.id} button", "Skip next delivery")
    end

    test "pauses and resumes", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      {:ok, view, _html} = live(conn, ~p"/account")

      view |> element("#subscription-#{subscription.id} button", "Pause") |> render_click()
      assert reload(subscription).state == :paused
      assert has_element?(view, "#subscription-#{subscription.id}", "Paused")

      view |> element("#subscription-#{subscription.id} button", "Resume") |> render_click()
      assert reload(subscription).state == :active
    end

    test "cancels", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      {:ok, view, _html} = live(conn, ~p"/account")

      view |> element("#subscription-#{subscription.id} button", "Cancel subscription") |> render_click()

      assert reload(subscription).state == :cancelled
      refute has_element?(view, "#subscription-#{subscription.id} button")
    end

    test "offers no changes inside the cutoff", %{conn: conn, user: user} do
      subscription = subscription(user, %{next_fulfillment_date: days_from_today(4)})
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "#subscription-#{subscription.id}", "It's too late to change your next delivery.")
      refute has_element?(view, "#subscription-#{subscription.id} button")
    end

    test "changes the size and how often", %{conn: conn, user: user} do
      subscription = subscription(user, %{})
      variant = Ash.get!(Edenflowers.Catalog.ProductVariant, subscription.product_variant_id)
      large = generate(product_variant(product_id: variant.product_id, size: :large, draft: false))
      {:ok, view, _html} = live(conn, ~p"/account")

      view
      |> form("#change-subscription-#{subscription.id}", %{
        "product_variant_id" => large.id,
        "interval_weeks" => "4"
      })
      |> render_submit()

      assert %{product_variant_id: large_id, interval_weeks: 4} = reload(subscription)
      assert large_id == large.id
      assert has_element?(view, "#subscription-#{subscription.id}", "Large · Every 4 weeks")
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
      view |> element("#subscription-#{subscription.id} button", "Pause") |> render_click()

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

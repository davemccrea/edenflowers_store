defmodule EdenflowersWeb.Account.AccountLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
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
      generate(course_registration(course_id: course.id, user_id: user.id, status: :confirmed))

      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "[data-testid=courses-table]", "Autumn Wreaths")
      assert has_element?(view, "[data-testid=courses-table]", "Booked")
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
          fulfillment_fee: "4.50",
          fulfillment_tax_rate: tax_rate.percentage,
          payment_status: :paid,
          ordered_at: DateTime.utc_now(),
          locale: "en-GB"
        ],
        overrides
      )

    order = generate(order(attrs))
    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))
    order
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end

defmodule EdenflowersWeb.Plugs.MaintenanceTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Courses
  alias Edenflowers.Orders
  alias EdenflowersWeb.PaymentLink

  test "redirects /back-soon to the homepage when maintenance mode is off", %{conn: conn} do
    conn = get(conn, "/back-soon")
    assert redirected_to(conn) == "/"
  end

  describe "when maintenance mode turns on or off under an open tab" do
    setup do
      on_exit(fn -> Application.delete_env(:edenflowers, :maintenance_mode) end)
    end

    test "sends the next storefront page to /back-soon", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/en/store")
      Application.put_env(:edenflowers, :maintenance_mode, true)

      assert {:error, {:redirect, %{to: "/back-soon"}}} = live_redirect(view, to: "/en/about")
    end

    test "lets a signed-in admin keep browsing", %{conn: conn} do
      admin = generate(admin_user()) |> with_token()
      conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)
      {:ok, view, _html} = live(conn, "/en/store")
      Application.put_env(:edenflowers, :maintenance_mode, true)

      assert {:ok, _view, _html} = live_redirect(view, to: "/en/about")
    end
  end

  describe "when maintenance mode is on" do
    setup do
      Application.put_env(:edenflowers, :maintenance_mode, true)
      on_exit(fn -> Application.delete_env(:edenflowers, :maintenance_mode) end)
    end

    test "redirects store pages to /back-soon", %{conn: conn} do
      assert conn |> get("/en/store") |> redirected_to() == "/back-soon"
    end

    test "lets the sign-in page through", %{conn: conn} do
      assert conn |> get("/sign-in") |> html_response(200)
    end

    test "lets an order's payment link through", %{conn: conn} do
      admin = generate(admin_user())
      tax_rate = generate(tax_rate())
      pickup = generate(fulfillment_option(tax_rate_id: tax_rate.id, base_price: "0.00"))

      {:ok, order} =
        Orders.place_custom_order(
          %{
            customer_name: "Anna Holm",
            customer_email: "anna@example.com",
            fulfillment_option_id: pickup.id,
            fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 1),
            locale: "en-GB",
            email_customer?: false,
            line_items: [
              %{
                "kind" => "custom",
                "product_name" => "Funeral spray",
                "unit_price" => "85.00",
                "tax_rate_id" => tax_rate.id,
                "quantity" => "1"
              }
            ]
          },
          actor: admin
        )

      assert conn |> get(PaymentLink.path_for(order)) |> html_response(200) =~ "Pay for your order"
    end

    test "lets a course booking's payment link through", %{conn: conn} do
      registration = course_registration_with_payment_link()

      assert conn |> get(PaymentLink.path_for(registration)) |> html_response(200) =~ "Pay for your booking"
    end

    test "lets admin paths reach their own auth check", %{conn: conn} do
      assert conn |> get("/admin/orders") |> redirected_to() =~ "/sign-in"
    end

    test "lets a signed-in admin reach public pages", %{conn: conn} do
      admin = generate(admin_user()) |> with_token()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Helpers.store_in_session(admin)
        |> get(~p"/en/about")

      assert html_response(conn, 200)
    end
  end

  defp course_registration_with_payment_link do
    admin = generate(admin_user())
    registration = generate(course_registration(status: :confirmed, amount: Decimal.new("85.00")))
    {:ok, registration} = Courses.open_registration_payment_link(registration, actor: admin)
    registration
  end
end

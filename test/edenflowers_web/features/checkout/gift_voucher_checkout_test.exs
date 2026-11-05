defmodule EdenflowersWeb.Checkout.GiftVoucherCheckoutTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Mox
  import Phoenix.LiveViewTest

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders

  setup :verify_on_exit!

  defp cart do
    order =
      order_in_payment(
        payment_intent_id: nil,
        customer_phone_number: "040 1234567",
        fulfillment_method: :pickup,
        fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 7)
      )

    Orders.get_order_for_checkout!(order.id, actor: nil)
  end

  defp apply_code(view, form, code),
    do: view |> element(form) |> render_submit(%{"gift_voucher" => %{"code" => code}})

  describe "store checkout" do
    test "a voucher lowers what the card is asked to pay, and can be taken off", %{conn: conn} do
      order = cart()
      voucher = generate(gift_voucher(amount: Decimal.new("10.00")))
      {:ok, view, _html} = live(with_cart(conn, order), ~p"/checkout")

      assert apply_code(view, "#checkout-gift-voucher-form", "WRONG") =~ "couldn&#39;t find that gift voucher"

      apply_code(view, "#checkout-gift-voucher-form", voucher.code)
      to_pay = Edenflowers.Format.currency(Decimal.sub(order.grand_total, 10), order.locale)
      assert has_element?(view, "[data-testid=gift-voucher-applied]", "Gift voucher")
      assert has_element?(view, "#payment-button", to_pay)

      view |> element("[data-testid=gift-voucher-applied] button", "Remove") |> render_click()
      refute has_element?(view, "[data-testid=gift-voucher-applied]")
    end

    test "a voucher that pays it all places the order without the card form", %{conn: conn} do
      order = cart()
      voucher = generate(gift_voucher(amount: Decimal.new("500.00")))
      {:ok, view, _html} = live(with_cart(conn, order), ~p"/checkout")

      apply_code(view, "#checkout-gift-voucher-form", voucher.code)
      refute has_element?(view, "#payment-element")

      view |> element("#checkout-form-4") |> render_submit()

      assert_redirect(view, ~p"/checkout/complete/#{order.id}")
      assert Orders.get_order_by_id!(order.id, authorize?: false).state == :placed
    end
  end

  describe "course checkout" do
    test "a voucher that pays it all books the places without the card form", %{conn: conn} do
      course = generate(course())
      registration = generate(course_registration(course_id: course.id, amount: Decimal.new("85.00")))
      voucher = generate(gift_voucher(amount: Decimal.new("100.00")))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.slug}?registration=#{registration.id}")
      apply_code(view, "#course-gift-voucher-form", voucher.code)
      refute has_element?(view, "#payment-element")

      assert {:error, {:live_redirect, %{to: to}}} = view |> element("#course-payment-form") |> render_submit()
      assert to == ~p"/courses/bookings/#{registration.id}"
      assert Edenflowers.Courses.get_registration_by_id!(registration.id, authorize?: false).status == :confirmed
    end

    test "a voucher that pays part leaves the card the rest", %{conn: conn} do
      course = generate(course())
      registration = generate(course_registration(course_id: course.id, amount: Decimal.new("85.00")))
      voucher = generate(gift_voucher(amount: Decimal.new("30.00")))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.slug}?registration=#{registration.id}")
      apply_code(view, "#course-gift-voucher-form", voucher.code)

      assert has_element?(view, "#payment-button", "55")

      expect(StripeAPI.Mock, :create_payment_intent, fn 5500, _metadata, nil ->
        {:ok, %{id: "pi_rest", client_secret: "pi_rest_secret", amount: 5500}}
      end)

      view |> element("#course-payment-form") |> render_submit()
      assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_rest_secret"})
    end
  end
end

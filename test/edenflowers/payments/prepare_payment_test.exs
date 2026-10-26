defmodule Edenflowers.Payments.PreparePaymentTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.Courses
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Payments.Errors.NotPayable

  setup :verify_on_exit!

  defp refusal({:error, error}), do: NotPayable.find(error).reason

  defp stock(variant, quantity) do
    variant |> Ash.Changeset.for_update(:update, %{stock_quantity: quantity}) |> Ash.update!(authorize?: false)
  end

  describe "preparing a store checkout payment" do
    setup do
      variant = generate(product_variant(product_id: generate(product()).id, stock_quantity: 1))
      %{order: order_in_payment(product_variant_id: variant.id), variant: variant}
    end

    test "refuses a cart over stock, then charges the cart's current total once it fits", ctx do
      sold_out = stock(ctx.variant, 0)

      assert {:error, error} = Orders.prepare_checkout_payment(ctx.order.id, actor: nil)
      assert %{reason: :over_stock, line_items: [%{product_variant_id: variant_id}]} = NotPayable.find(error)
      assert variant_id == ctx.variant.id

      stock(sold_out, 1)
      %{payment_intent_id: payment_intent_id} = ctx.order
      cents = StripeAPI.to_stripe_amount(ctx.order.grand_total)

      expect(StripeAPI.Mock, :update_payment_intent, fn ^payment_intent_id, ^cents -> {:ok, %{}} end)

      expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
        {:ok, %{id: payment_intent_id, client_secret: "pi_secret", customer: nil}}
      end)

      assert {:ok, %{client_secret: "pi_secret"}} = Orders.prepare_checkout_payment(ctx.order.id, actor: nil)
    end

    test "refuses a cart holding only add-ons" do
      add_on = generate(product(product_category_id: generate(product_category(add_on: true)).id))
      order = order_in_payment(product_variant_id: generate(product_variant(product_id: add_on.id)).id)

      assert refusal(Orders.prepare_checkout_payment(order.id, actor: nil)) == :add_ons_only
    end

    test "refuses an order placed since the page read it", ctx do
      Ash.Seed.update!(ctx.order, %{state: :placed})

      assert {:error, _not_a_cart} = Orders.prepare_checkout_payment(ctx.order.id, actor: nil)
    end
  end

  describe "preparing a course checkout payment" do
    setup do
      course = generate(course(total_places: 2))

      %{
        course: course,
        registration: generate(course_registration(course_id: course.id, seats: 2, amount: Decimal.new("170.00")))
      }
    end

    test "refuses a course that filled up or closed since the booking was made", ctx do
      generate(course_registration(course_id: ctx.course.id, status: :confirmed, seats: 1))

      assert refusal(Courses.prepare_registration_checkout_payment(ctx.registration.id, ctx.course.id)) ==
               :not_enough_places

      Ash.Seed.update!(ctx.course, %{register_before: Date.add(Edenflowers.ShopTime.today(), -1)})

      assert refusal(Courses.prepare_registration_checkout_payment(ctx.registration.id, ctx.course.id)) ==
               :booking_closed
    end

    test "charges the booking's price", ctx do
      registration_id = ctx.registration.id

      expect(StripeAPI.Mock, :create_payment_intent, fn 17_000, %{"course_registration_id" => ^registration_id}, nil ->
        {:ok, %{id: "pi_course", client_secret: "pi_course_secret", amount: 17_000}}
      end)

      assert {:ok, %{client_secret: "pi_course_secret", payable: %{payment_intent_id: "pi_course"}}} =
               Courses.prepare_registration_checkout_payment(registration_id, ctx.course.id)
    end
  end

  describe "preparing a payment link payment" do
    setup do
      admin = generate(admin_user())

      {:ok, registration} =
        Courses.add_registration_manually(
          %{
            name: "Ada Lovelace",
            email: "ada@example.com",
            seats: 1,
            course_id: generate(course()).id,
            locale: "fi",
            email_customer?: false
          },
          actor: admin
        )

      %{registration: registration}
    end

    test "needs the link's token" do
      assert {:error, _not_found} = Courses.prepare_registration_link_payment("not-the-token", "85.00")
    end

    test "charges the balance without anyone's saved cards, even with a customer signed in", ctx do
      generate(payment(course_registration_id: ctx.registration.id, method: :cash, amount: Decimal.new("30.00")))
      signed_in = generate(admin_user(admin: false))

      expect(StripeAPI.Mock, :create_payment_intent, fn 5500, _metadata, nil ->
        {:ok, %{id: "pi_link", client_secret: "pi_link_secret", amount: 5500}}
      end)

      assert {:ok, %{client_secret: "pi_link_secret", payable: payable}} =
               Courses.prepare_registration_link_payment(ctx.registration.payment_link_token, "55.00", actor: signed_in)

      assert Decimal.equal?(payable.balance, "55.00")
      assert payable.payment_intent_id == "pi_link"
    end

    test "refuses a stale displayed balance without preparing a payment", ctx do
      generate(payment(course_registration_id: ctx.registration.id, method: :cash, amount: Decimal.new("30.00")))

      assert refusal(Courses.prepare_registration_link_payment(ctx.registration.payment_link_token, "85.00")) ==
               :balance_changed

      assert is_nil(Ash.reload!(ctx.registration, authorize?: false).payment_intent_id)
    end

    test "requires the displayed balance", ctx do
      assert {:error, _missing_balance} =
               ctx.registration.__struct__
               |> Ash.ActionInput.for_action(:prepare_link_payment, %{token: ctx.registration.payment_link_token})
               |> Ash.run_action()
    end

    test "refuses a link that closed once nothing was owed", ctx do
      generate(payment(course_registration_id: ctx.registration.id, method: :cash, amount: Decimal.new("85.00")))

      assert refusal(Courses.prepare_registration_link_payment(ctx.registration.payment_link_token, "85.00")) ==
               :link_closed
    end

    test "refuses a cancelled booking's link even while an old intent remains usable", ctx do
      Ash.Seed.update!(ctx.registration, %{status: :cancelled, payment_intent_id: "pi_processing"})

      assert refusal(Courses.prepare_registration_link_payment(ctx.registration.payment_link_token, "85.00")) ==
               :link_closed
    end
  end
end

defmodule EdenflowersWeb.Courses.CoursePayLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Mox
  import Phoenix.LiveViewTest

  alias Edenflowers.Courses
  alias Edenflowers.External.StripeAPI

  setup :verify_on_exit!

  setup do
    admin = generate(admin_user())
    course = generate(course(name: "Autumn wreaths", price: "85.00"))

    registration =
      generate(course_registration(course_id: course.id, status: :confirmed, seats: 2, amount: Decimal.new("170.00")))

    {:ok, _paid} = Courses.record_registration_payment(registration, "50.00", :cash, actor: admin)
    {:ok, registration} = Courses.open_registration_payment_link(registration, actor: admin)

    %{admin: admin, registration: registration}
  end

  test "shows the booking and a payment form for what it still owes", %{conn: conn, registration: registration} do
    registration_id = registration.id
    generate(course_registration(status: :confirmed, name: "Somebody Else", email: "else@example.com"))

    expect(StripeAPI.Mock, :create_payment_intent, fn 12_000, %{"course_registration_id" => ^registration_id}, nil ->
      {:ok, %{id: "pi_link", client_secret: "pi_link_secret", amount: 12_000}}
    end)

    {:ok, view, _html} = live(conn, ~p"/en/courses/pay/#{registration.payment_link_token}")

    assert has_element?(view, "h1", "Pay for your booking")
    assert has_element?(view, "dl", "Autumn wreaths")
    assert has_element?(view, "[data-testid=pay-total]", "170.00")
    assert has_element?(view, "[data-testid=pay-balance]", "120.00")
    assert has_element?(view, ~s|#pay-form[data-client-secret="pi_link_secret"]|)
    refute render(view) =~ "Somebody Else"
    refute render(view) =~ "else@example.com"
  end

  test "shows only the amount due while nothing is paid", %{conn: conn, admin: admin} do
    registration = generate(course_registration(status: :confirmed, amount: Decimal.new("85.00")))
    {:ok, registration} = Courses.open_registration_payment_link(registration, actor: admin)

    expect(StripeAPI.Mock, :create_payment_intent, fn 8500, _metadata, nil ->
      {:ok, %{id: "pi_link", client_secret: "pi_link_secret", amount: 8500}}
    end)

    {:ok, view, _html} = live(conn, ~p"/en/courses/pay/#{registration.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-total]", "85.00")
    refute has_element?(view, "[data-testid=pay-balance]")
    refute render(view) =~ "Paid so far"
  end

  test "says so once the booking is settled", %{conn: conn, admin: admin, registration: registration} do
    {:ok, _paid} = Courses.record_registration_payment(registration, "120.00", :cash, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/en/courses/pay/#{registration.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-paid]")
    refute has_element?(view, "#pay-form")
  end

  test "rejects a link that doesn't match a booking", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/en"}}} = live(conn, ~p"/en/courses/pay/not-a-token")
  end

  test "back from Stripe, shows the booking paid once the payment is recorded", %{
    conn: conn,
    registration: registration
  } do
    registration = Ash.Seed.update!(registration, %{payment_intent_id: "pi_link"})

    {:ok, view, _html} = live(conn, ~p"/en/courses/pay/#{registration.payment_link_token}?redirect_status=succeeded")

    assert has_element?(view, "[data-testid=pay-confirming]")

    {:ok, :completed} =
      Edenflowers.Payments.complete(%{
        id: "pi_link",
        metadata: %{"course_registration_id" => registration.id},
        amount_received: 12_000
      })

    assert has_element?(view, "[data-testid=pay-paid]")
  end
end

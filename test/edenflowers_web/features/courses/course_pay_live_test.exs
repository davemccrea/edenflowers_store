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

    generate(payment(course_registration_id: registration.id, amount: Decimal.new("50.00")))
    {:ok, registration} = Courses.open_registration_payment_link(registration, actor: admin)

    %{admin: admin, registration: registration}
  end

  test "shows the booking and a payment form for what it still owes", %{conn: conn, registration: registration} do
    generate(course_registration(status: :confirmed, name: "Somebody Else", email: "else@example.com"))

    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}")

    assert has_element?(view, "h1", "Pay for your booking")
    assert has_element?(view, "dl", "Autumn wreaths")
    assert has_element?(view, "dd", "Minimossen")
    assert has_element?(view, "dd", registration.reference)
    refute has_element?(view, "#pay-form input[type=email]")
    assert has_element?(view, "[data-testid=pay-total]", "170.00")
    assert has_element?(view, "[data-testid=pay-balance]", "120.00")
    assert has_element?(view, ~s|#pay-form[data-amount="12000"]|)
    refute render(view) =~ "Somebody Else"
    refute render(view) =~ "else@example.com"
  end

  test "says so once the booking is refunded", %{conn: conn, registration: registration} do
    generate(payment(course_registration_id: registration.id, amount: "-50.00"))

    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-refunded]")
    refute has_element?(view, "[data-testid=pay-booked]")
    refute has_element?(view, ".flower-bloom")
    refute has_element?(view, "#pay-form")
  end

  test "a booking cannot be created without a valid email", %{admin: admin, registration: registration} do
    for email <- [nil, "", "not-an-email"] do
      assert {:error, %Ash.Error.Invalid{}} =
               Courses.add_registration_manually(
                 %{name: "Ada", email: email, seats: 1, course_id: registration.course_id},
                 actor: admin
               )
    end
  end

  test "creates a PaymentIntent for what it still owes when the customer pays", %{
    conn: conn,
    registration: registration
  } do
    registration_id = registration.id

    expect(StripeAPI.Mock, :create_payment_intent, fn 12_000, %{"course_registration_id" => ^registration_id}, nil ->
      {:ok, %{id: "pi_link", client_secret: "pi_link_secret", amount: 12_000}}
    end)

    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}")
    view |> element("#pay-form") |> render_submit()

    assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_link_secret"})
  end

  test "shows only the amount due while nothing is paid", %{conn: conn, admin: admin} do
    registration = generate(course_registration(status: :confirmed, amount: Decimal.new("85.00")))
    {:ok, registration} = Courses.open_registration_payment_link(registration, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-total]", "85.00")
    refute has_element?(view, "[data-testid=pay-balance]")
    refute render(view) =~ "Paid so far"
  end

  test "reloads instead of charging a balance changed since the page was shown", %{
    conn: conn,
    registration: registration
  } do
    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}")
    generate(payment(course_registration_id: registration.id, amount: "20.00"))

    assert {:error, {:live_redirect, %{to: path}}} = view |> element("#pay-form") |> render_submit()
    assert path == ~p"/pay/courses/#{registration.payment_link_token}"
    refute_push_event(view, "stripe:process_payment", %{})
    assert is_nil(Ash.reload!(registration, authorize?: false).payment_intent_id)
  end

  test "keeps the course translated when displaying the prepared booking", %{conn: conn, registration: registration} do
    course = Ash.get!(Edenflowers.Courses.Course, registration.course_id, authorize?: false)
    Ash.Seed.update!(course, %{translations: %{"fi" => %{"name" => "Syksyiset kranssit"}}})
    registration = Ash.Seed.update!(registration, %{locale: "fi"})

    expect(StripeAPI.Mock, :create_payment_intent, fn 12_000, _metadata, nil ->
      {:ok, %{id: "pi_translated", client_secret: "secret", amount: 12_000}}
    end)

    conn = put_req_header(conn, "accept-language", "fi")
    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}")
    assert has_element?(view, "dl", "Syksyiset kranssit")
    view |> element("#pay-form") |> render_submit()
    assert has_element?(view, "dl", "Syksyiset kranssit")
    assert_push_event(view, "stripe:process_payment", %{client_secret: "secret"})
  end

  test "says so once the booking is settled", %{conn: conn, registration: registration} do
    generate(payment(course_registration_id: registration.id, amount: Decimal.new("120.00")))

    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-paid]")
    assert has_element?(view, "h1", "Thank you, Ada.")
    assert has_element?(view, "p[data-testid=pay-booked]", "You're booked.")
    refute has_element?(view, "[data-testid=pay-booked].font-serif")
    refute render(view) =~ "This booking is paid."
    assert has_element?(view, ".flower-bloom")
    assert has_element?(view, "dt", "Total paid")
    assert has_element?(view, "[data-testid=pay-total]", "170.00")
    refute render(view) =~ "Paid so far"
    refute has_element?(view, "[data-testid=pay-balance]")
    refute has_element?(view, "#pay-form")
  end

  test "a cancelled booking does not promise places or request payment", %{conn: conn, registration: registration} do
    Ash.Seed.update!(registration, %{status: :cancelled})
    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-cancelled]")
    refute has_element?(view, "[data-testid=pay-booked]")
    refute has_element?(view, ".flower-bloom")
    refute has_element?(view, "#pay-form")
  end

  test "a token alone does not grant receipt access", %{conn: conn, registration: registration} do
    generate(payment(course_registration_id: registration.id, amount: "120.00"))
    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}")

    refute has_element?(view, ~s|a[href="/courses/bookings/#{registration.id}/receipt"]|)
    assert conn |> get(~p"/courses/bookings/#{registration.id}/receipt") |> response(404)
  end

  test "rejects a link that doesn't match a booking", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/en"}}} = live(conn, ~p"/pay/courses/not-a-token")
  end

  test "an invite paid after its course confirms the booking without promising a future place", %{conn: conn} do
    course = generate(course(date: Date.add(Edenflowers.ShopTime.today(), -1)))

    registration =
      generate(
        course_registration(
          course_id: course.id,
          amount: Decimal.new("85.00"),
          payment_link_token: "invite-after-course",
          payment_intent_id: "pi_after_course"
        )
      )

    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}?redirect_status=succeeded")

    assert has_element?(view, "[data-testid=pay-confirming]")

    {:ok, :completed} =
      Edenflowers.Payments.complete(%{
        id: "pi_after_course",
        metadata: %{"course_registration_id" => registration.id},
        amount_received: 8500
      })

    assert has_element?(view, "h1[data-testid=pay-paid]", "Thank you, Ada.")
    assert Ash.reload!(registration, authorize?: false).status == :confirmed
    refute has_element?(view, "[data-testid=pay-booked]")
    refute has_element?(view, "[data-testid=pay-confirming]")
    refute has_element?(view, "#pay-form")
  end

  test "back from Stripe, shows the booking paid once the payment is recorded", %{
    conn: conn,
    registration: registration
  } do
    registration = Ash.Seed.update!(registration, %{payment_intent_id: "pi_link"})

    {:ok, view, _html} = live(conn, ~p"/pay/courses/#{registration.payment_link_token}?redirect_status=succeeded")

    assert has_element?(view, "[data-testid=pay-confirming]")
    assert has_element?(view, ".flower-waiting")
    refute has_element?(view, "[data-testid=pay-paid]")
    refute has_element?(view, "#pay-form")

    {:ok, :completed} =
      Edenflowers.Payments.complete(%{
        id: "pi_link",
        metadata: %{"course_registration_id" => registration.id},
        amount_received: 12_000
      })

    assert has_element?(view, "[data-testid=pay-paid]")
  end
end

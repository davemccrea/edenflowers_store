defmodule EdenflowersWeb.Courses.CourseBookingLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Courses

  describe "/courses/bookings/:id" do
    test "shows a guest their booking without its email address", %{conn: conn} do
      course = generate(course(name: "Autumn Wreaths"))

      registration =
        generate(course_registration(course_id: course.id, status: :confirmed, seats: 2, reference: "T123"))

      {:ok, view, html} = live(conn, ~p"/courses/bookings/#{registration.id}")

      assert has_element?(view, "h1", "You're booked")
      assert has_element?(view, "dd", "Autumn Wreaths")
      assert has_element?(view, "dd", "T123")
      refute html =~ registration.email
    end

    test "waits for payment before calling a registration booked", %{conn: conn} do
      registration = generate(course_registration(payment_intent_id: "pi_booking"))

      {:ok, view, _html} = live(conn, ~p"/courses/bookings/#{registration.id}")

      assert has_element?(view, "[data-testid=booking-confirming]", "Confirming your payment")
      refute has_element?(view, "h1", "You're booked")
      refute render(view) =~ "To cancel"

      Courses.confirm_registration_payment!(registration, "pi_booking", %{amount_paid: registration.amount},
        actor: Edenflowers.Actors.system_actor()
      )

      assert has_element?(view, "h1", "You're booked")
      refute has_element?(view, "[data-testid=booking-confirming]")
      assert render(view) =~ "To cancel"
    end

    test "says nothing about cancelling after today's course has ended", %{conn: conn} do
      course = generate(course(date: Edenflowers.ShopTime.today(), start_time: ~T[00:00:00], end_time: ~T[00:00:01]))
      registration = generate(course_registration(course_id: course.id, status: :confirmed))

      {:ok, view, _html} = live(conn, ~p"/courses/bookings/#{registration.id}")

      refute render(view) =~ "To cancel"
    end

    test "says when the booking has been cancelled", %{conn: conn} do
      registration = generate(course_registration(status: :cancelled))

      {:ok, view, _html} = live(conn, ~p"/courses/bookings/#{registration.id}")

      assert has_element?(view, "h1", "Booking cancelled")
      refute render(view) =~ "To cancel"
    end

    test "says nothing about cancelling once the course is over", %{conn: conn} do
      course = generate(course(date: Date.add(Edenflowers.ShopTime.today(), -1)))
      registration = generate(course_registration(course_id: course.id, status: :confirmed))

      {:ok, view, _html} = live(conn, ~p"/courses/bookings/#{registration.id}")

      refute render(view) =~ "To cancel"
    end

    test "a failed redirect payment discards the unpaid registration and returns to the course", %{conn: conn} do
      registration = generate(course_registration(status: :pending))

      assert {:error, {:live_redirect, %{to: to, flash: %{"error" => error}}}} =
               live(conn, ~p"/courses/bookings/#{registration.id}?redirect_status=failed")

      assert to == "/en/courses/#{registration.course_id}"
      assert error =~ "Your payment didn't go through"

      assert {:error, _discarded} = Courses.get_registration_by_id(registration.id, authorize?: false)
    end

    test "an unknown booking goes back to the courses", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/en/courses", flash: %{"error" => "Booking not found."}}}} =
               live(conn, ~p"/courses/bookings/#{Ash.UUID.generate()}")
    end
  end

  describe "/courses/bookings/:id/receipt" do
    setup %{conn: conn} do
      user = generate(admin_user(admin: false)) |> with_token()
      conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(user)

      %{conn: conn, user: user}
    end

    @tag :typst
    test "opens a confirmed booking's receipt for its owner", %{conn: conn, user: user} do
      registration = generate(course_registration(user_id: user.id, status: :confirmed, reference: "T456"))
      generate(payment(course_registration_id: registration.id, amount: registration.amount))

      conn = get(conn, ~p"/courses/bookings/#{registration.id}/receipt")

      assert "%PDF" <> _ = response(conn, 200)
      assert get_resp_header(conn, "content-disposition") == [~s|inline; filename="eden-flowers-T456.pdf"|]
    end

    test "has no receipt for a booking not yet paid", %{conn: conn, user: user} do
      registration = generate(course_registration(user_id: user.id, status: :pending))

      assert conn |> get(~p"/courses/bookings/#{registration.id}/receipt") |> response(404)
    end

    test "won't show another customer's receipt", %{conn: conn} do
      other = generate(admin_user(admin: false))
      registration = generate(course_registration(user_id: other.id, status: :confirmed))
      generate(payment(course_registration_id: registration.id, amount: registration.amount))

      assert conn |> get(~p"/courses/bookings/#{registration.id}/receipt") |> response(404)
    end
  end
end

defmodule EdenflowersWeb.Courses.CoursesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator
  import Mox

  setup :verify_on_exit!

  describe "/courses" do
    test "points at the newsletter when nothing is scheduled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/courses")

      assert has_element?(view, "[data-testid=no-courses] a[href='#newsletter']")
    end

    test "lists upcoming courses and offers details but no booking button for full ones", %{conn: conn} do
      open = generate(course(name: "Autumn Wreaths"))
      full = generate(course(name: "Winter Bouquets", total_places: 2))
      generate(course_registration(course_id: full.id, seats: 2, status: :confirmed))

      {:ok, view, _html} = live(conn, ~p"/en/courses")

      assert has_element?(
               view,
               ~s|[data-testid=courses-list] a[href="/en/courses/#{open.id}#book"][aria-label="Book a place: Autumn Wreaths"]|,
               "Book a place"
             )

      assert has_element?(view, "[data-testid=courses-list]", "Fully booked")
      assert has_element?(view, ~s|h3 a[href="/en/courses/#{full.id}"]|, "Winter Bouquets")
      refute has_element?(view, ~s|a[href="/en/courses/#{full.id}#book"]|)
    end
  end

  describe "course list decision details" do
    test "shows the price and a single booking link per open course", %{conn: conn} do
      course = generate(course(name: "Autumn Wreaths", price: "85.00"))

      {:ok, view, _html} = live(conn, ~p"/en/courses")

      assert has_element?(view, "[data-testid=courses-list]", "85")
      assert has_element?(view, ~s|h3 a[href="/en/courses/#{course.id}"]|, "Autumn Wreaths")
      assert view |> element(~s|a[href="/en/courses/#{course.id}#book"]|) |> render() =~ "Book a place"
      assert has_element?(view, "[aria-labelledby=coming-up] a[href='#newsletter']")
    end

    test "a closed course explains its status without a booking link", %{conn: conn} do
      course = generate(course(register_before: Date.add(Edenflowers.ShopTime.today(), -1)))

      {:ok, view, _html} = live(conn, ~p"/en/courses")

      assert has_element?(view, "[data-testid=course-availability]", "Booking closed")
      assert has_element?(view, ~s|h3 a[href="/en/courses/#{course.id}"]|)
      refute has_element?(view, ~s|a[href="/en/courses/#{course.id}#book"]|)
      assert has_element?(view, "[aria-labelledby=coming-up] a[href='#newsletter']")
    end
  end

  describe "/courses/:id" do
    test "books places and shows the payment form", %{conn: conn} do
      course = generate(course(name: "Autumn Wreaths", price: "85.00", total_places: 8))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "3"})
      |> render_submit()

      assert has_element?(view, ~s|#course-payment-form[data-amount="25500"]|)
      assert has_element?(view, "#payment-button", "255")
      assert has_element?(view, "#pay-heading[phx-mounted][tabindex='-1']")
    end

    test "creates the PaymentIntent when the customer pays", %{conn: conn} do
      course = generate(course(price: "85.00", total_places: 8))

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn 25_500,
                                                                             %{"course_registration_id" => _},
                                                                             _customer ->
        {:ok, %{id: "pi_course", client_secret: "pi_course_secret", amount: 25_500}}
      end)

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "3"})
      |> render_submit()

      view |> element("#course-payment-form") |> render_submit()

      assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_course_secret"})
    end

    test "paying for places taken meanwhile reopens the form instead of charging", %{conn: conn} do
      course = generate(course(total_places: 2))
      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "2"})
      |> render_submit()

      generate(course_registration(course_id: course.id, seats: 1, status: :confirmed))
      view |> element("#course-payment-form") |> render_submit()

      refute_push_event(view, "stripe:process_payment", %{})
      refute has_element?(view, "#course-payment-form")
      assert has_element?(view, "#booking-form")
    end

    test "Change booking reopens the form and revises the same registration", %{conn: conn} do
      course = generate(course(price: "85.00"))
      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "1"})
      |> render_submit()

      [registration] = Ash.read!(Edenflowers.Courses.CourseRegistration, authorize?: false)
      view |> element("button[phx-click=change]") |> render_click()

      refute has_element?(view, "#course-payment-form")
      assert has_element?(view, ~s|#booking-form input[name="form[email]"][value="ada@example.com"]|)

      view |> form("#booking-form", form: %{seats: "2"}) |> render_submit()

      assert has_element?(view, ~s|#course-payment-form[data-amount="17000"]|)
      assert [%{id: id, seats: 2}] = Ash.read!(Edenflowers.Courses.CourseRegistration, authorize?: false)
      assert id == registration.id
    end

    test "paying after a change brings the PaymentIntent up to the new price", %{conn: conn} do
      course = generate(course(price: "85.00"))

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn 8500, _, _ ->
        {:ok, %{id: "pi_course", client_secret: "pi_course_secret", amount: 8500}}
      end)

      expect(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn "pi_course", 17_000 -> {:ok, %{}} end)

      expect(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: "pi_course"} ->
        {:ok, %{id: "pi_course", client_secret: "pi_course_secret"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "1"})
      |> render_submit()

      view |> element("#course-payment-form") |> render_submit()
      view |> element("button[phx-click=change]") |> render_click()
      view |> form("#booking-form", form: %{seats: "2"}) |> render_submit()
      view |> element("#course-payment-form") |> render_submit()

      assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_course_secret"})
    end

    @tag capture_log: true
    test "goes to the confirmed booking when payment completes while it is being changed", %{conn: conn} do
      course = generate(course())
      test_pid = self()

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn 8500, metadata, _ ->
        send(test_pid, {:registration_id, metadata["course_registration_id"]})
        {:ok, %{id: "pi_completed", client_secret: "pi_completed_secret", amount: 8500}}
      end)

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "1"})
      |> render_submit()

      view |> element("#course-payment-form") |> render_submit()
      assert_receive {:registration_id, id}
      view |> element("button[phx-click=change]") |> render_click()

      assert {:ok, :completed} =
               Edenflowers.Payments.complete(%{
                 id: "pi_completed",
                 metadata: %{"course_registration_id" => id},
                 amount_received: 8500
               })

      view |> form("#booking-form", form: %{seats: "2"}) |> render_submit()

      assert_redirect(view, ~p"/courses/bookings/#{id}")
      assert %{status: :confirmed, seats: 1} = Edenflowers.Courses.get_registration_by_id!(id, authorize?: false)
    end

    test "shows the seat error when others booked the places first", %{conn: conn} do
      course = generate(course(total_places: 4))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      generate(course_registration(course_id: course.id, seats: 3, status: :confirmed))

      html =
        view
        |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "2"})
        |> render_submit()

      assert html =~ "only 1 place left"
      refute has_element?(view, "#course-payment-form")
      assert has_element?(view, "#booking-form [data-testid=seats-select] option", "1")
      refute has_element?(view, "#booking-form [data-testid=seats-select] option[value='2']")
    end

    test "a closed course offers the newsletter instead of a form", %{conn: conn} do
      course = generate(course(register_before: Date.add(Edenflowers.ShopTime.today(), -1)))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      assert has_element?(view, "[data-testid=booking-closed]")
      refute has_element?(view, "#booking-form")
    end

    test "an unknown course is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/en/courses/#{Ash.UUID.generate()}") end
      assert_error_sent 404, fn -> get(conn, ~p"/en/courses/not-a-uuid") end
    end
  end

  describe "/courses/:id when already booked" do
    setup %{conn: conn} do
      user = generate(admin_user(admin: false)) |> with_token()

      conn = log_in(conn, user)

      %{conn: conn, user: user}
    end

    test "reminds the customer of their places and links to their bookings", %{conn: conn, user: user} do
      course = generate(course())
      generate(course_registration(course_id: course.id, user_id: user.id, status: :confirmed, seats: 2))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      assert has_element?(view, "[data-testid=already-booked]", "You have 2 places on this course.")
      assert has_element?(view, ~s|[data-testid=already-booked] a[href="/account#upcoming"]|)
      assert has_element?(view, "#book", "Book more places")
    end

    test "says nothing about an unpaid booking", %{conn: conn, user: user} do
      course = generate(course())
      generate(course_registration(course_id: course.id, user_id: user.id, status: :pending))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      refute has_element?(view, "[data-testid=already-booked]")
    end
  end

  describe "/courses/bookings/:id" do
    test "waits for payment to confirm the booking", %{conn: conn} do
      registration = generate(course_registration(payment_intent_id: "pi_x"))

      {:ok, view, _html} = live(conn, ~p"/courses/bookings/#{registration.id}")
      assert has_element?(view, "[data-testid=booking-confirming]")
      refute has_element?(view, "h1", "You're booked")
    end

    test "says how to cancel a confirmed booking", %{conn: conn} do
      registration = generate(course_registration(status: :confirmed))

      {:ok, _view, html} = live(conn, ~p"/courses/bookings/#{registration.id}")
      assert html =~ "To cancel, reply to your confirmation email."
    end
  end

  describe "structured data" do
    test "an upcoming course is an event in Helsinki time", %{conn: conn} do
      course = generate(course(date: ~D[2099-06-01], start_time: ~T[10:00:00], end_time: ~T[14:00:00]))

      json_ld = conn |> get(~p"/en/courses/#{course.id}") |> html_response(200) |> json_ld()

      assert %{"@type" => "Event", "startDate" => "2099-06-01T10:00:00+03:00", "offers" => offers} = json_ld
      assert %{"price" => "85.00", "availability" => "https://schema.org/InStock"} = offers
    end

    test "a past course has none", %{conn: conn} do
      course = generate(course(date: Date.add(Edenflowers.ShopTime.today(), -1)))

      assert conn |> get(~p"/en/courses/#{course.id}") |> html_response(200) |> json_ld() == nil
    end
  end

  defp json_ld(html) do
    case Regex.run(~r|<script type="application/ld\+json">(.*?)</script>|s, html) do
      [_, json] -> Jason.decode!(json)
      nil -> nil
    end
  end
end

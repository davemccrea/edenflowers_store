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

    test "lists upcoming courses and keeps full ones as unlinked rows", %{conn: conn} do
      open = generate(course(name: "Autumn Wreaths"))
      full = generate(course(name: "Winter Bouquets", total_places: 2))
      generate(course_registration(course_id: full.id, seats: 2, status: :confirmed))

      {:ok, view, _html} = live(conn, ~p"/en/courses")

      assert has_element?(view, ~s|[data-testid=courses-list] a[href="/en/courses/#{open.id}"]|, "Autumn Wreaths")
      assert has_element?(view, "[data-testid=courses-list]", "Fully booked")
      refute has_element?(view, ~s|a[href="/en/courses/#{full.id}"]|)
    end
  end

  describe "/courses/:id" do
    test "shows the language the course is taught in, here and in the listing", %{conn: conn} do
      course = generate(course(language: :en))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")
      assert has_element?(view, "[data-testid=course-language]", "English")

      {:ok, view, _html} = live(conn, ~p"/en/courses")
      assert has_element?(view, "[data-testid=course-language]", "In English")
    end

    test "names the course's late-cancellation fee, or promises a full refund without one", %{conn: conn} do
      course = generate(course(late_cancellation_fee: "20.00"))
      free = generate(course(late_cancellation_fee: "0"))

      {:ok, _view, html} = live(conn, ~p"/en/courses/#{course.id}")
      assert html =~ "a €20.00 late-cancellation fee is kept"

      {:ok, _view, html} = live(conn, ~p"/en/courses/#{free.id}")
      assert html =~ "Cancel at least 7 days before the course for a full refund."
      refute html =~ "late-cancellation fee"
    end

    test "books places and shows the payment form", %{conn: conn} do
      course = generate(course(name: "Autumn Wreaths", price: "85.00", total_places: 8))

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn 25_500,
                                                                             %{"course_registration_id" => _},
                                                                             _customer ->
        {:ok, %{id: "pi_course", client_secret: "pi_course_secret", amount: 25_500}}
      end)

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "3"})
      |> render_submit()

      assert has_element?(view, "#course-payment-form[data-client-secret=pi_course_secret]")
      assert has_element?(view, "#payment-button", "255")
      assert has_element?(view, "#pay-heading[phx-mounted][tabindex='-1']")
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
      course = generate(course(register_before: Date.add(Date.utc_today(), -1)))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      assert has_element?(view, "[data-testid=booking-closed]")
      refute has_element?(view, "#booking-form")
    end

    test "a past course still renders", %{conn: conn} do
      course = generate(course(date: Date.add(Date.utc_today(), -7), register_before: Date.add(Date.utc_today(), -8)))

      {:ok, _view, html} = live(conn, ~p"/en/courses/#{course.id}")

      assert html =~ course.name
    end

    test "an unknown course is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/en/courses/#{Ash.UUID.generate()}") end
      assert_error_sent 404, fn -> get(conn, ~p"/en/courses/not-a-uuid") end
    end
  end

  describe "/courses/:id when already booked" do
    setup %{conn: conn} do
      user = generate(admin_user(admin: false)) |> with_token()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> AshAuthentication.Plug.Helpers.store_in_session(user)

      %{conn: conn, user: user}
    end

    test "reminds the customer of their places and links to their bookings", %{conn: conn, user: user} do
      course = generate(course())
      generate(course_registration(course_id: course.id, user_id: user.id, status: :confirmed, seats: 2))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      assert has_element?(view, "[data-testid=already-booked]", "You have 2 places on this course.")
      assert has_element?(view, ~s|[data-testid=already-booked] a[href="/account#courses-heading"]|)
      assert has_element?(view, "#book-heading", "Book more places")
    end

    test "says nothing about an unpaid booking", %{conn: conn, user: user} do
      course = generate(course())
      generate(course_registration(course_id: course.id, user_id: user.id, status: :pending))

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      refute has_element?(view, "[data-testid=already-booked]")
    end
  end

  describe "/courses/bookings/:id" do
    test "shows the booking straight away, before payment confirms", %{conn: conn} do
      registration = generate(course_registration(payment_intent_id: "pi_x"))

      {:ok, _view, html} = live(conn, ~p"/courses/bookings/#{registration.id}")
      assert html =~ "You&#39;re booked"
    end

    test "names the course's late-cancellation fee", %{conn: conn} do
      course = generate(course(late_cancellation_fee: "15.00"))
      registration = generate(course_registration(course_id: course.id, payment_intent_id: "pi_x"))

      {:ok, _view, html} = live(conn, ~p"/courses/bookings/#{registration.id}")
      assert html =~ "a €15.00 late-cancellation fee is kept"
    end

    test "releases the hold and goes back to the course when a redirect payment fails", %{conn: conn} do
      registration = generate(course_registration(payment_intent_id: "pi_x"))
      expect(Edenflowers.External.StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_x"} -> {:ok, %{id: "pi_x"}} end)

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/courses/bookings/#{registration.id}?redirect_status=failed")

      assert to == ~p"/en/courses/#{registration.course_id}"
      assert flash["error"] =~ "didn't go through"

      {:ok, registration} =
        Edenflowers.Courses.get_registration_by_id(registration.id, actor: Edenflowers.Actors.system_actor())

      assert registration.status == :cancelled
      assert registration.payment_intent_id == nil
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

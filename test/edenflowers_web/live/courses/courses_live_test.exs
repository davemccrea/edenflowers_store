defmodule EdenflowersWeb.Courses.CoursesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator
  import Mox

  setup :verify_on_exit!

  describe "/courses" do
    test "points at the newsletter when nothing is scheduled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/courses")

      assert has_element?(view, "[data-testid=no-courses] a[href='#newsletter']")
    end

    test "lists upcoming courses and keeps full ones as unlinked rows", %{conn: conn} do
      open = generate(course(name: "Autumn Wreaths"))
      full = generate(course(name: "Winter Bouquets", total_places: 2))
      generate(course_registration(course_id: full.id, seats: 2, status: :confirmed))

      {:ok, view, _html} = live(conn, ~p"/courses")

      assert has_element?(view, ~s|[data-testid=courses-list] a[href="/courses/#{open.id}"]|, "Autumn Wreaths")
      assert has_element?(view, "[data-testid=courses-list]", "Fully booked")
      refute has_element?(view, ~s|a[href="/courses/#{full.id}"]|)
    end
  end

  describe "/courses/:id" do
    test "books places and shows the payment form", %{conn: conn} do
      course = generate(course(name: "Autumn Wreaths", price: "85.00", total_places: 8))

      expect(Edenflowers.External.StripeAPI.Mock, :create_course_payment_intent, fn registration ->
        assert Decimal.equal?(registration.amount, "255.00")
        {:ok, %{id: "pi_course", client_secret: "pi_course_secret", amount: 25_500}}
      end)

      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "3"})
      |> render_submit()

      assert has_element?(view, "#course-payment-form[data-client-secret=pi_course_secret]")
      assert has_element?(view, "#payment-button", "255")
      assert has_element?(view, "#pay-heading[phx-mounted][tabindex='-1']")
    end

    test "shows the seat error when others booked the places first", %{conn: conn} do
      course = generate(course(total_places: 4))

      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}")

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

      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}")

      assert has_element?(view, "[data-testid=booking-closed]")
      refute has_element?(view, "#booking-form")
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

      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}")

      assert has_element?(view, "[data-testid=already-booked]", "You have 2 places on this course.")
      assert has_element?(view, ~s|[data-testid=already-booked] a[href="/account#courses-heading"]|)
      assert has_element?(view, "#book-heading", "Book more places")
    end

    test "says nothing about an unpaid booking", %{conn: conn, user: user} do
      course = generate(course())
      generate(course_registration(course_id: course.id, user_id: user.id, status: :pending))

      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}")

      refute has_element?(view, "[data-testid=already-booked]")
    end
  end

  describe "/courses/bookings/:id" do
    test "flips from pending to booked when the payment confirms", %{conn: conn} do
      registration = generate(course_registration(payment_intent_id: "pi_x"))

      {:ok, view, _html} = live(conn, ~p"/courses/bookings/#{registration.id}")
      assert has_element?(view, "[data-testid=booking-status]", "Confirming your payment")

      Edenflowers.Courses.confirm_registration_payment!(registration, actor: Edenflowers.Actors.system_actor())

      assert render(view) =~ "You&#39;re booked"
    end
  end

  defp with_token(user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end

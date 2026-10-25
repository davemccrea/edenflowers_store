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

    test "promises a full refund 7 days before the course", %{conn: conn} do
      course = generate(course())

      {:ok, _view, html} = live(conn, ~p"/en/courses/#{course.id}")
      assert html =~ "Cancel at least 7 days before the course for a full refund."
    end

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

    test "changing an unpaid registration returns to the booking form", %{conn: conn} do
      course = generate(course())
      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "1"})
      |> render_submit()

      view |> element("button[phx-click=change]") |> render_click()

      assert has_element?(view, "#booking-form")
      refute has_element?(view, "#course-payment-form")
    end

    test "keeps checkout when its payment is still processing", %{conn: conn} do
      course = generate(course())

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn 8500, _, _ ->
        {:ok, %{id: "pi_processing", client_secret: "pi_processing_secret", amount: 8500}}
      end)

      expect(Edenflowers.External.StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_processing"} ->
        {:error, :processing}
      end)

      expect(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: "pi_processing"} ->
        {:ok, %{status: "processing"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/en/courses/#{course.id}")

      view
      |> form("#booking-form", form: %{name: "Ada Lovelace", email: "ada@example.com", seats: "1"})
      |> render_submit()

      view |> element("#course-payment-form") |> render_submit()
      view |> element("button[phx-click=change]") |> render_click()

      assert has_element?(view, "#course-payment-form")
      refute has_element?(view, "#booking-form")
      assert render(view) =~ "Your payment is still being confirmed."
    end

    test "goes to the confirmed booking when payment completes before Change booking", %{conn: conn} do
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

      assert {:ok, :completed} =
               Edenflowers.Payments.complete(%{
                 id: "pi_completed",
                 metadata: %{"course_registration_id" => id},
                 amount_received: 8500
               })

      view |> element("button[phx-click=change]") |> render_click()
      assert_redirect(view, ~p"/courses/bookings/#{id}")
      assert Edenflowers.Courses.get_registration_by_id!(id, authorize?: false).status == :confirmed
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

    test "a past course still renders", %{conn: conn} do
      course =
        generate(
          course(
            date: Date.add(Edenflowers.ShopTime.today(), -7),
            register_before: Date.add(Edenflowers.ShopTime.today(), -8)
          )
        )

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

    test "a failed return keeps a processing payment instead of crashing or retrying discard", %{conn: conn} do
      registration = generate(course_registration(payment_intent_id: "pi_processing"))

      expect(Edenflowers.External.StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_processing"} ->
        {:error, :processing}
      end)

      expect(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn %{payment_intent_id: "pi_processing"} ->
        {:ok, %{status: "processing"}}
      end)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/courses/bookings/#{registration.id}?redirect_status=failed")

      assert to == ~p"/courses/bookings/#{registration.id}"
      {:ok, view, _html} = live(conn, to)
      assert has_element?(view, "[data-testid=booking-confirming]")
    end

    @tag capture_log: true
    test "a failed return reports an unexpected Stripe failure without deleting or crashing", %{conn: conn} do
      registration = generate(course_registration(payment_intent_id: "pi_offline"))
      expect(Edenflowers.External.StripeAPI.Mock, :cancel_payment_intent, fn _ -> {:error, :offline} end)
      expect(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn _ -> {:error, :offline} end)

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/courses/bookings/#{registration.id}?redirect_status=failed")

      assert to == ~p"/courses/bookings/#{registration.id}"
      assert flash["error"] =~ "Payment is temporarily unavailable"
      assert {:ok, _} = Edenflowers.Courses.get_registration_by_id(registration.id, authorize?: false)
    end

    test "a failed return still deletes checkout when its cancellation webhook clears the intent", %{conn: conn} do
      registration = generate(course_registration(payment_intent_id: "pi_cancelled"))

      expect(Edenflowers.External.StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_cancelled"} ->
        assert {:ok, _} =
                 Edenflowers.Payments.cancel(%{
                   id: "pi_cancelled",
                   metadata: %{"course_registration_id" => registration.id}
                 })

        {:ok, %{status: "canceled"}}
      end)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/courses/bookings/#{registration.id}?redirect_status=failed")

      assert to == ~p"/en/courses/#{registration.course_id}"
      assert {:error, _} = Edenflowers.Courses.get_registration_by_id(registration.id, authorize?: false)
    end

    test "discards the unpaid registration and goes back to the course when a redirect payment fails", %{conn: conn} do
      registration = generate(course_registration(payment_intent_id: "pi_x"))
      expect(Edenflowers.External.StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_x"} -> {:ok, %{id: "pi_x"}} end)

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/courses/bookings/#{registration.id}?redirect_status=failed")

      assert to == ~p"/en/courses/#{registration.course_id}"
      assert flash["error"] =~ "didn't go through"

      assert {:error, _discarded} =
               Edenflowers.Courses.get_registration_by_id(registration.id, actor: Edenflowers.Actors.system_actor())
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

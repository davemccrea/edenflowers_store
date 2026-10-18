defmodule EdenflowersWeb.Admin.CoursesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  use Oban.Testing, repo: Edenflowers.Repo

  import Phoenix.LiveViewTest
  import Generator
  import Swoosh.TestAssertions

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn}
  end

  test "lists confirmed bookings with seat counts, hides unpaid ones and shows cancelled ones apart", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths", total_places: 10))

    generate(
      course_registration(course_id: course.id, status: :confirmed, name: "Anna", email: "anna@example.com", seats: 3)
    )

    generate(course_registration(course_id: course.id, status: :pending, name: "Pending Pete"))
    generate(course_registration(course_id: course.id, status: :cancelled, name: "Cancelled Carl"))

    {:ok, view, html} = live(conn, ~p"/admin/courses")

    assert html =~ "Autumn wreaths"
    assert html =~ "3 / 10 seats"
    assert has_element?(view, "li", "Anna")
    assert has_element?(view, "li", "+2")
    assert has_element?(view, ~s|a[href="https://app.fastmail.com/mail/compose?bcc=anna%40example.com"]|)
    refute html =~ "Pending Pete"
    assert has_element?(view, "[data-status=cancelled]", "Cancelled Carl")
  end

  test "View in store opens the public courses listing in a new tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    assert has_element?(view, ~s|a[href="/courses"][target="_blank"]|, "View in store")
  end

  test "a link from the Overview opens the booking's course and highlights the booking", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths"))
    other_course = generate(course(name: "Spring posies"))
    registration = generate(course_registration(course_id: course.id, status: :confirmed, name: "Anna"))
    generate(course_registration(course_id: other_course.id, status: :confirmed, name: "Birgitta"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses?#{[booking: registration.id]}")

    assert has_element?(view, "#course-#{course.id}[open]")
    refute has_element?(view, "#course-#{other_course.id}[open]")
    assert has_element?(view, ~s|#registration-#{registration.id}[aria-current="true"]|, "Anna")
  end

  test "cancelling a booking moves it to the cancelled list", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, name: "Anna"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-click="cancel"][phx-value-id="#{registration.id}"]|) |> render_click()

    assert has_element?(view, "[data-status=cancelled]", "Anna")
    refute has_element?(view, ~s|button[phx-value-id="#{registration.id}"]|)
    assert Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false).status == :cancelled
  end

  describe "adding a booking" do
    defp add_booking(view, course, payment_link?, email_customer?) do
      view |> element(~s|button[phx-value-course-id="#{course.id}"]|) |> render_click()

      view
      |> form("#booking-form-#{course.id}",
        form: %{
          name: "Birgitta",
          email: "birgitta@example.com",
          seats: "2",
          locale: "en-GB",
          payment_link?: payment_link?,
          email_customer?: email_customer?
        }
      )
      |> render_submit()

      Ash.read_one!(Edenflowers.Courses.CourseRegistration, authorize?: false)
    end

    test "to pay later emails a confirmation without a payment link", %{conn: conn} do
      course = generate(course(name: "Autumn wreaths", total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      assert has_element?(view, ~s|button[phx-value-course-id="#{course.id}"]|)
      view |> element(~s|button[phx-value-course-id="#{course.id}"]|) |> render_click()
      assert has_element?(view, "#booking-form-#{course.id}", "Send a payment link")
      assert has_element?(view, "#booking-form-#{course.id}", "Record the payment later")
      view |> element("#booking-form-#{course.id} button", "Close") |> render_click()

      registration = add_booking(view, course, "false", "true")

      assert has_element?(view, "li", "Birgitta")
      assert has_element?(view, "li", "To collect")
      assert render(view) =~ "2 / 10 seats"
      assert render(view) =~ "1 to collect"
      refute registration.payment_link_token

      assert %{success: 1} = Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        refute email.text_body =~ "/pay/"
        assert email.text_body =~ "You pay at the course"
      end)
    end

    test "with a payment link puts it in the confirmation", %{conn: conn} do
      course = generate(course(total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      registration = add_booking(view, course, "true", "true")
      assert registration.payment_link_token

      assert %{success: 1} = Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.to == [{"", "birgitta@example.com"}]
        assert email.text_body =~ "/pay/#{registration.payment_link_token}"
        assert email.text_body =~ "You can still pay at the course instead"
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/courses")
      assert render(view) =~ "Resend payment link"
    end

    test "without emailing sends nothing, even from the scheduler", %{conn: conn} do
      course = generate(course(total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      registration = add_booking(view, course, "true", "false")
      assert registration.payment_link_token

      refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
      perform_job(Edenflowers.Courses.Schedulers.SendConfirmationEmail, %{})
      refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
      assert_no_email_sent()
    end
  end

  test "a past course stays listed, marked past, until its bookings are settled", %{conn: conn} do
    owing = past_course("Spring posies")
    generate(course_registration(course_id: owing.id, status: :confirmed))
    settled = past_course("Winter garlands")

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    assert has_element?(view, "#course-#{owing.id}", "Past")
    refute has_element?(view, "#course-#{settled.id}")
  end

  defp past_course(name),
    do: generate(course(name: name)) |> Ash.Seed.update!(%{date: Date.add(Date.utc_today(), -7)})

  test "marking a booking paid clears it from the still-to-pay list", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, name: "Birgitta"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> form("#mark-paid-#{registration.id}", %{payment_method: "mobilepay"}) |> render_submit()

    refute has_element?(view, "li", "To collect")
    refute render(view) =~ ~r"\d+ to collect"

    assert [%{method: :mobilepay}] = Ash.load!(registration, :payments, authorize?: false).payments
  end

  describe "payment link" do
    test "only a booking owing money offers one, alongside the quick payment form", %{conn: conn} do
      owing = generate(course_registration(status: :confirmed, name: "Birgitta"))
      paid = generate(course_registration(status: :confirmed, name: "Anna"))

      Ash.Seed.seed!(Edenflowers.Payments.Payment, %{
        course_registration_id: paid.id,
        amount: paid.amount,
        method: :cash,
        paid_at: DateTime.utc_now()
      })

      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      assert has_element?(view, "#mark-paid-#{owing.id}")
      assert has_element?(view, ~s|button[phx-click="email_payment_link"][phx-value-id="#{owing.id}"]|)
      assert has_element?(view, ~s|button[phx-click="open_payment_link"][phx-value-id="#{owing.id}"]|)
      refute has_element?(view, ~s|button[phx-value-id="#{paid.id}"]|, "payment link")
    end

    test "emailing opens the link, sends it, and asks before sending again", %{conn: conn} do
      registration = generate(course_registration(status: :confirmed, name: "Birgitta", email: "birgitta@example.com"))

      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      assert view
             |> element(~s|button[phx-click="email_payment_link"][phx-value-id="#{registration.id}"]|)
             |> render_click() =~ "Payment link emailed."

      registration = Ash.reload!(registration, authorize?: false)

      assert_email_sent(fn email ->
        assert email.to == [{"", "birgitta@example.com"}]
        assert email.text_body =~ EdenflowersWeb.PaymentLink.url_for(registration)
      end)

      button = element(view, ~s|button[phx-click="email_payment_link"][phx-value-id="#{registration.id}"]|)
      assert render(button) =~ "Resend payment link"
      assert render(button) =~ "Last sent"
      assert has_element?(view, "#copy-payment-link-#{registration.id}")

      assert has_element?(
               view,
               "#payment-link-url-#{registration.id}",
               "/courses/pay/#{registration.payment_link_token}"
             )
    end

    test "paying at the course after the link was sent settles the booking and its link reads paid", %{conn: conn} do
      registration = generate(course_registration(status: :confirmed, name: "Birgitta"))
      {:ok, view, _html} = live(conn, ~p"/admin/courses")
      view |> element(~s|button[phx-click="open_payment_link"][phx-value-id="#{registration.id}"]|) |> render_click()

      view |> form("#mark-paid-#{registration.id}", %{payment_method: "cash"}) |> render_submit()

      refute has_element?(view, "li", "To collect")
      registration = Ash.reload!(registration, authorize?: false)
      {:ok, pay_view, _html} = live(build_conn(), ~p"/courses/pay/#{registration.payment_link_token}")
      assert has_element?(pay_view, "[data-testid=pay-paid]")
    end
  end

  test "a booking paid with Stripe has nothing to collect", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, payment_intent_id: nil))

    generate(
      payment(course_registration_id: registration.id, amount: registration.amount, payment_intent_id: "pi_paid")
    )

    generate(course_registration(course_id: registration.course_id, status: :pending, payment_intent_id: "pi_open"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    refute has_element?(view, "li", "To collect")
    refute render(view) =~ ~r"\d+ to collect"
  end

  test "links a Stripe booking to its payment in the Stripe dashboard", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, payment_intent_id: nil))
    generate(payment(course_registration_id: registration.id, amount: registration.amount, payment_intent_id: "pi_123"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    assert has_element?(view, ~s|a[href$="/payments/pi_123"]|, "Stripe")
  end

  test "removing a seat frees it but leaves the sale the receipt shows", %{conn: conn} do
    course = generate(course(total_places: 10))

    registration =
      generate(course_registration(course_id: course.id, status: :confirmed, seats: 3, amount: Decimal.new("255.00")))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-click="remove_seat"][phx-value-id="#{registration.id}"]|) |> render_click()

    assert render(view) =~ "2 / 10 seats"
    reloaded = Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false)
    assert reloaded.seats == 3
    assert reloaded.removed_seats == 1
    assert Decimal.equal?(reloaded.amount, "255.00")
  end

  test "the last seat can't be removed, only cancelled" do
    registration = generate(course_registration(status: :confirmed, seats: 2))
    admin = %{admin: true}

    assert {:ok, registration} = Edenflowers.Courses.remove_registration_seat(registration, actor: admin)
    assert {:error, _} = Edenflowers.Courses.remove_registration_seat(registration, actor: admin)
  end
end

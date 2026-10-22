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

    assert has_element?(view, ~s|a[href="/en/courses"][target="_blank"]|, "View in store")
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

    view |> element(~s|button[phx-click="open_cancel"][phx-value-id="#{registration.id}"]|) |> render_click()
    refute has_element?(view, ~s|#cancel-form input[name="cancel[refund]"]|)
    view |> form("#cancel-form") |> render_submit()

    assert has_element?(view, "[data-status=cancelled]", "Anna")
    refute has_element?(view, ~s|button[phx-click="open_cancel"][phx-value-id="#{registration.id}"]|)
    assert Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false).status == :cancelled
  end

  describe "cancelling a paid booking" do
    setup do
      today = Edenflowers.ShopTime.today()

      course = generate(course(date: Date.add(today, 3), register_before: today))

      registration =
        generate(course_registration(course_id: course.id, status: :confirmed, amount: Decimal.new("85.00")))

      generate(payment(course_registration_id: registration.id, method: :cash, amount: Decimal.new("85.00")))

      %{registration: registration}
    end

    defp open_cancel(view, registration) do
      view |> element(~s|button[phx-click="open_cancel"][phx-value-id="#{registration.id}"]|) |> render_click()
    end

    test "keeps what Jennie doesn't refund and leaves the rest to hand back", %{conn: conn, registration: registration} do
      {:ok, view, _html} = live(conn, ~p"/admin/courses")
      open_cancel(view, registration)
      assert has_element?(view, ~s|#cancel-form input[name="cancel[refund]"][value="85.00"]|)

      view |> form("#cancel-form", cancel: %{refund: "50,00", reason: "Ill that day"}) |> render_submit()

      assert has_element?(view, "#registration-#{registration.id}", "To refund €50.00")

      view |> element("#settle-#{registration.id}", "To refund") |> render_click()
      assert has_element?(view, "#settlement-drawer dl", "Kept")
      assert has_element?(view, "#settlement-drawer dl", "€35.00")
      assert has_element?(view, "#settlement-drawer", "Ill that day")
      assert has_element?(view, "#settlement-drawer", "Cancellation emailed to #{registration.email}.")

      view
      |> form("#refund-#{registration.id}", refund: %{payment_method: "cash"})
      |> put_submitter(~s|#refund-#{registration.id} button[value="record"]|)
      |> render_submit()

      refute has_element?(view, "#registration-#{registration.id}", "To refund")
      registration = Ash.load!(registration, [:amount_paid], authorize?: false, reuse_values?: false)
      assert Decimal.equal?(registration.amount_paid, "35.00")
    end

    test "an amount over what was paid keeps the drawer open with the error", %{
      conn: conn,
      registration: registration
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/courses")
      open_cancel(view, registration)

      view |> form("#cancel-form", cancel: %{refund: "90"}) |> render_submit()

      assert has_element?(view, "#cancel-drawer [role=alert]", "Enter an amount from €0 to €85.00.")
      assert Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false).status == :confirmed
    end
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
      assert has_element?(view, "#booking-drawer #booking-form-#{course.id}", "Send a payment link")
      assert has_element?(view, "#booking-form-#{course.id}", "Pays later")
      view |> element("#booking-form-#{course.id} button", "Cancel") |> render_click()
      refute has_element?(view, "#booking-form-#{course.id}")

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
        assert email.text_body =~ "Or pay at the course if you prefer."
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/courses")
      assert render(view) =~ "Resend payment link"
    end

    test "the confirmation can be sent again from the booking's menu", %{conn: conn} do
      registration = generate(course_registration(status: :confirmed, email: "birgitta@example.com"))
      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      button = element(view, ~s|button[phx-click="email_confirmation"][phx-value-id="#{registration.id}"]|)
      assert render(button) =~ "Email confirmation"
      assert render_click(button) =~ "Confirmation emailed."

      assert_email_sent(fn email -> assert email.to == [{"", "birgitta@example.com"}] end)

      button = element(view, ~s|button[phx-click="email_confirmation"][phx-value-id="#{registration.id}"]|)
      assert render(button) =~ "Resend confirmation"
      assert render(button) =~ "Last sent"
    end

    test "without emailing queues nothing", %{conn: conn} do
      course = generate(course(total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      registration = add_booking(view, course, "true", "false")
      assert registration.payment_link_token
      refute registration.confirmation_emailed_at

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
    do: generate(course(name: name)) |> Ash.Seed.update!(%{date: Date.add(Edenflowers.ShopTime.today(), -7)})

  test "marking a booking paid clears it from the still-to-pay list", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, name: "Birgitta"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    refute has_element?(view, "#mark-paid-#{registration.id}")

    view |> element("#settle-#{registration.id}", "To collect") |> render_click()

    assert has_element?(view, "#settlement-drawer", "Birgitta")
    assert has_element?(view, "#settlement-drawer dl", "To collect")

    view |> form("#mark-paid-#{registration.id}", %{payment_method: "mobilepay"}) |> render_submit()

    refute has_element?(view, "li", "To collect")
    refute render(view) =~ ~r"\d+ to collect"
    refute has_element?(view, "#settle-#{registration.id}")
    refute has_element?(view, "#mark-paid-#{registration.id}")

    assert [%{method: :mobilepay}] = Ash.load!(registration, :payments, authorize?: false).payments
  end

  describe "payment link" do
    test "only a booking owing money offers one, alongside Record payment", %{conn: conn} do
      owing = generate(course_registration(status: :confirmed, name: "Birgitta"))
      paid = generate(course_registration(status: :confirmed, name: "Anna"))

      Ash.Seed.seed!(Edenflowers.Payments.Payment, %{
        course_registration_id: paid.id,
        amount: paid.amount,
        method: :cash,
        paid_at: DateTime.utc_now()
      })

      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      assert has_element?(view, "#settle-#{owing.id}")
      refute has_element?(view, "#settle-#{paid.id}")
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
      view |> element("#settle-#{registration.id}") |> render_click()

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

  describe "goodwill refund" do
    defp paid_booking(payment_opts) do
      registration = generate(course_registration(status: :confirmed, name: "Anna", amount: Decimal.new("85.00")))
      generate(payment([course_registration_id: registration.id, amount: Decimal.new("85.00")] ++ payment_opts))
      registration
    end

    defp refund_menu_item(registration), do: "#registration-actions-#{registration.id} button"

    test "Refund is offered only once nothing is to collect", %{conn: conn} do
      unpaid = generate(course_registration(status: :confirmed, name: "Unpaid Ulla"))
      paid = paid_booking(method: :cash)

      {:ok, view, _html} = live(conn, ~p"/admin/courses")

      refute has_element?(view, refund_menu_item(unpaid), "Refund")
      assert has_element?(view, refund_menu_item(paid), "Refund")
      refute has_element?(view, "#goodwill-refund-#{paid.id}")

      view |> element(refund_menu_item(paid), "Refund") |> render_click()

      assert has_element?(view, "#settlement-drawer #goodwill-refund-#{paid.id}")
      refute has_element?(view, "#goodwill-refund-#{paid.id}.hidden")
    end

    test "a part refund by cash is recorded with its reason and leaves nothing to collect", %{conn: conn} do
      registration = paid_booking(method: :cash)

      {:ok, view, _html} = live(conn, ~p"/admin/courses")
      view |> element(refund_menu_item(registration), "Refund") |> render_click()

      view
      |> form("#goodwill-refund-#{registration.id}-form",
        goodwill_refund: %{amount: "20", how: "cash", note: "Ran short of moss"}
      )
      |> render_submit()

      assert has_element?(view, "#registration-#{registration.id}", "Goodwill refund €20.00 · Cash")
      assert has_element?(view, "#registration-#{registration.id}", "Ran short of moss")
      refute has_element?(view, "#registration-#{registration.id}", "To collect")
      refute has_element?(view, "#registration-#{registration.id}", "To refund")
      refute has_element?(view, "#goodwill-refund-#{registration.id}")
    end

    test "a part refund by Stripe is sent and recorded, leaving nothing to collect", %{conn: conn} do
      registration = paid_booking(payment_intent_id: "pi_booking")

      Edenflowers.External.StripeAPI.Mock
      |> Mox.stub(:list_refunds, fn "pi_booking" -> {:ok, []} end)
      |> Mox.expect(:create_refund, fn "pi_booking", 2_000, _key, %{"reason" => "goodwill"} ->
        {:ok, %{id: "re_booking", payment_intent: "pi_booking", amount: 2_000, status: "succeeded"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/courses")
      view |> element(refund_menu_item(registration), "Refund") |> render_click()

      view
      |> form("#goodwill-refund-#{registration.id}-form", goodwill_refund: %{amount: "20.00", how: "stripe"})
      |> render_submit()

      assert has_element?(view, "#registration-#{registration.id}", "Goodwill refund €20.00 · Stripe")
      refute has_element?(view, "#registration-#{registration.id}", "To collect")
      refute has_element?(view, "#registration-#{registration.id}", "To refund")
    end
  end
end

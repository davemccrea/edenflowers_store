defmodule EdenflowersWeb.Admin.CourseDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  use Oban.Testing, repo: Edenflowers.Repo

  import Phoenix.LiveViewTest
  import Generator
  import Swoosh.TestAssertions

  setup :log_in_admin

  test "lists confirmed bookings with seat counts, hides unpaid ones and shows cancelled ones apart", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths", total_places: 10))

    generate(
      course_registration(course_id: course.id, status: :confirmed, name: "Anna", email: "anna@example.com", seats: 3)
    )

    generate(course_registration(course_id: course.id, status: :pending, name: "Pending Pete"))
    generate(course_registration(course_id: course.id, status: :cancelled, name: "Cancelled Carl"))

    {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.id}")

    assert html =~ "Autumn wreaths"
    assert html =~ "3 / 10 seats"
    assert has_element?(view, "li", "Anna")
    assert has_element?(view, "li", "+2")
    assert has_element?(view, ~s|a[href="https://app.fastmail.com/mail/compose?bcc=anna%40example.com"]|)
    refute html =~ "Pending Pete"
    assert has_element?(view, "[data-status=cancelled]", "Cancelled Carl")
  end

  test "a link from the Overview highlights the booking and shows only its course", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths"))
    other_course = generate(course(name: "Spring posies"))
    registration = generate(course_registration(course_id: course.id, status: :confirmed, name: "Anna"))
    generate(course_registration(course_id: other_course.id, status: :confirmed, name: "Birgitta"))

    {:ok, view, html} = live(conn, ~p"/admin/courses/#{course.id}?#{[booking: registration.id]}")

    assert has_element?(view, ~s|#registration-#{registration.id}[aria-current="true"]|, "Anna")
    refute html =~ "Birgitta"
  end

  test "links to the course's edit form", %{conn: conn} do
    course = generate(course())

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

    assert has_element?(view, ~s|a[href="/admin/courses/#{course.id}/edit"]|, "Edit course")
  end

  test "an unknown course goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/courses", flash: %{"error" => "Course not found."}}}} =
             live(conn, ~p"/admin/courses/#{Ecto.UUID.generate()}")
  end

  test "cancelling a booking moves it to the cancelled list", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, name: "Anna"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")

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

    test "after the course's deadline, prefills the refund less the course's fee", %{
      conn: conn,
      registration: registration
    } do
      Edenflowers.Courses.Course
      |> Ash.get!(registration.course_id, authorize?: false)
      |> Ash.Seed.update!(%{cancellation_fee_percent: 50})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      open_cancel(view, registration)

      assert has_element?(view, ~s|#cancel-form input[name="cancel[refund]"][value="42.50"]|)
    end

    test "before the course's deadline, prefills a full refund", %{conn: conn, registration: registration} do
      Edenflowers.Courses.Course
      |> Ash.get!(registration.course_id, authorize?: false)
      |> Ash.Seed.update!(%{cancellation_fee_percent: 50, cancellation_days: 2})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      open_cancel(view, registration)

      assert has_element?(view, ~s|#cancel-form input[name="cancel[refund]"][value="85.00"]|)
    end

    test "keeps what Jennie doesn't refund and leaves the rest to hand back", %{conn: conn, registration: registration} do
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      open_cancel(view, registration)
      assert has_element?(view, ~s|#cancel-form input[name="cancel[refund]"][value="85.00"]|)

      view |> form("#cancel-form", cancel: %{refund: "50,00", message: "Ill that day"}) |> render_submit()

      assert has_element?(view, "#registration-#{registration.id}", "To refund €50.00")

      view |> element("#settle-#{registration.id}", "To refund") |> render_click()
      assert has_element?(view, "#settlement-drawer dl", "Kept")
      assert has_element?(view, "#settlement-drawer dl", "€35.00")
      assert has_element?(view, "#settlement-drawer", "Ill that day")
      assert has_element?(view, "#settlement-drawer", "Cancellation emailed to #{registration.email}.")

      view |> form("#refund-#{registration.id}-form", refund: %{how: "cash"}) |> render_submit()

      refute has_element?(view, "#registration-#{registration.id}", "To refund")
      registration = Ash.load!(registration, [:amount_paid], authorize?: false, reuse_values?: false)
      assert Decimal.equal?(registration.amount_paid, "35.00")
    end

    test "an amount over what was paid keeps the drawer open with the error", %{
      conn: conn,
      registration: registration
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      open_cancel(view, registration)

      view |> form("#cancel-form", cancel: %{refund: "90"}) |> render_submit()

      assert has_element?(view, "#cancel-drawer [role=alert]", "Enter an amount from €0 to €85.00.")
      assert Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false).status == :confirmed
    end
  end

  describe "adding a booking" do
    test "records an initial received payment with its method", %{conn: conn} do
      course = generate(course())
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")
      view |> element(~s|button[phx-click="new_booking"]|) |> render_click()
      assert has_element?(view, "#booking-drawer", "Pay at the course")

      params = %{
        name: "Ada",
        email: "ada@example.com",
        seats: "1",
        locale: "en-GB",
        email_customer?: "false",
        payment_method: "cash",
        amount: "85,00"
      }

      view |> form("#booking-form-#{course.id}", form: Map.delete(params, :amount)) |> render_change()
      assert has_element?(view, ~s|input[name="form[amount]"]|)
      view |> form("#booking-form-#{course.id}", form: params) |> render_submit()

      booking = Ash.read_one!(Edenflowers.Courses.CourseRegistration, authorize?: false, load: [:payments, :balance])
      assert booking.status == :confirmed
      assert [%{method: :cash, amount: amount}] = booking.payments
      assert Decimal.equal?(amount, "85.00")
      assert Decimal.equal?(booking.balance, 0)
      refute booking.payment_link_token
    end

    test "collects a part payment through the shared settlement form and previews its receipt", %{conn: conn} do
      booking = generate(course_registration(status: :confirmed))
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{booking.course_id}")
      view |> element("#settle-#{booking.id}") |> render_click()

      view
      |> form("#payment-#{booking.id}-form",
        payment: %{amount: "30,00", payment_method: "cash", email_receipt: "false"}
      )
      |> render_change()

      assert has_element?(view, "#payment-#{booking.id}-form", "Record payment")

      view
      |> form("#payment-#{booking.id}-form",
        payment: %{amount: "30,00", payment_method: "cash", email_receipt: "false"}
      )
      |> render_submit()

      assert has_element?(view, "#settle-#{booking.id}", "To collect €55.00")
      assert [%{method: :cash}] = Ash.load!(booking, :payments, authorize?: false).payments
    end

    defp add_booking(view, course, email_customer?) do
      view |> element(~s|button[phx-click="new_booking"]|) |> render_click()

      view
      |> form("#booking-form-#{course.id}",
        form: %{
          name: "Birgitta",
          email: "birgitta@example.com",
          seats: "2",
          locale: "en-GB",
          email_customer?: email_customer?
        }
      )
      |> render_submit()

      Ash.read_one!(Edenflowers.Courses.CourseRegistration, authorize?: false)
    end

    test "confirms places and optionally emails without a receipt or automatic payment link", %{conn: conn} do
      course = generate(course(name: "Autumn wreaths", total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      view |> element(~s|button[phx-click="new_booking"]|) |> render_click()
      assert has_element?(view, "#booking-drawer #booking-form-#{course.id}", "Email booking confirmation")
      view |> element("#booking-form-#{course.id} button", "Cancel") |> render_click()
      refute has_element?(view, "#booking-form-#{course.id}")

      registration = add_booking(view, course, "true")

      assert registration.status == :confirmed
      refute registration.payment_link_token
      refute has_element?(view, "#invites")
      assert has_element?(view, "#bookings li", "Birgitta")
      assert render(view) =~ "2 / 10 seats"

      assert %{success: 1} = Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.to == [{"", "birgitta@example.com"}]
        refute email.text_body =~ "/pay/courses/"
        assert email.text_body =~ "Your 2 places on Autumn wreaths are confirmed."
        assert email.text_body =~ "Please pay at the course."
        assert email.attachments == []
      end)
    end

    test "unfinished website checkouts remain hidden and cannot be withdrawn", %{conn: conn} do
      course = generate(course())

      invite =
        generate(course_registration(course_id: course.id, payment_link_token: "tok", payment_intent_id: "pi_paid"))

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      refute has_element?(view, "#registration-#{invite.id}")
      refute has_element?(view, "#invites")
      refute has_element?(view, ~s|button[phx-click="withdraw_invite"]|)
      assert Ash.get!(Edenflowers.Courses.CourseRegistration, invite.id, authorize?: false).status == :pending
    end

    @tag :typst
    test "the confirmation can be sent again from the booking's menu", %{conn: conn} do
      registration =
        generate(course_registration(status: :confirmed, payment_intent_id: nil, email: "birgitta@example.com"))

      generate(
        payment(course_registration_id: registration.id, amount: registration.amount, payment_intent_id: "pi_paid")
      )

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")

      button = element(view, ~s|button[phx-value-kind="confirmation"][phx-value-id="#{registration.id}"]|)
      assert render(button) =~ "Email confirmation"
      render_click(button)
      assert view |> form("#email-form") |> render_submit() =~ "Confirmation emailed."

      assert_email_sent(fn email -> assert email.to == [{"", "birgitta@example.com"}] end)

      button = element(view, ~s|button[phx-value-kind="confirmation"][phx-value-id="#{registration.id}"]|)
      assert render(button) =~ "Resend confirmation"
      render_click(button)
      assert has_element?(view, "#email-drawer", "Last sent")
    end

    test "without emailing queues nothing", %{conn: conn} do
      course = generate(course(total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      registration = add_booking(view, course, "false")
      refute registration.payment_link_token
      refute registration.confirmation_emailed_at

      refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
      assert_no_email_sent()
    end
  end

  describe "payment link" do
    test "only a booking owing money offers one, and nothing to mark it paid by hand", %{conn: conn} do
      owing = generate(course_registration(status: :confirmed, name: "Birgitta"))
      paid = generate(course_registration(course_id: owing.course_id, status: :confirmed, name: "Anna"))

      Ash.Seed.seed!(Edenflowers.Payments.Payment, %{
        course_registration_id: paid.id,
        amount: paid.amount,
        method: :cash,
        paid_at: DateTime.utc_now()
      })

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{owing.course_id}")

      refute has_element?(view, "#settle-#{paid.id}")
      refute has_element?(view, ~s|button[phx-value-kind="payment_link"]|)

      view |> element("#settle-#{owing.id}") |> render_click()

      assert has_element?(view, ~s|button[phx-value-kind="payment_reminder"][phx-value-id="#{owing.id}"]|)
      assert has_element?(view, ~s|button[phx-click="open_payment_link"][phx-value-id="#{owing.id}"]|)
      refute has_element?(view, "#mark-paid-#{owing.id}")
    end

    test "emailing opens the link, sends it, and asks before sending again", %{conn: conn} do
      registration = generate(course_registration(status: :confirmed, name: "Birgitta", email: "birgitta@example.com"))

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      view |> element("#settle-#{registration.id}") |> render_click()

      view
      |> element(~s|#settlement-drawer button[phx-value-kind="payment_reminder"][phx-value-id="#{registration.id}"]|)
      |> render_click()

      assert has_element?(view, "#email-drawer-email-preview", "still to pay")
      refute has_element?(view, "#email-drawer-email-preview", "booked once")
      assert view |> form("#email-form") |> render_submit() =~ "Payment reminder sent."

      registration = Ash.reload!(registration, authorize?: false)

      assert_email_sent(fn email ->
        assert email.to == [{"", "birgitta@example.com"}]
        refute email.text_body =~ "booked once"
        assert email.text_body =~ EdenflowersWeb.PaymentLink.url_for(registration)
      end)

      button =
        element(
          view,
          ~s|#settlement-drawer button[phx-value-kind="payment_reminder"][phx-value-id="#{registration.id}"]|
        )

      assert render(button) =~ "Send payment reminder"
      render_click(button)
      assert has_element?(view, "#email-drawer", "Last sent")
      assert has_element?(view, "#copy-payment-link-#{registration.id}")

      assert has_element?(
               view,
               ~s|#payment-link-url-#{registration.id}[value$="/pay/courses/#{registration.payment_link_token}"]|
             )
    end
  end

  test "a booking paid with Stripe has nothing to collect", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, payment_intent_id: nil))

    generate(
      payment(course_registration_id: registration.id, amount: registration.amount, payment_intent_id: "pi_paid")
    )

    generate(course_registration(course_id: registration.course_id, status: :pending, payment_intent_id: "pi_open"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")

    refute has_element?(view, "li", "To collect")
  end

  test "links a Stripe booking to its payment in the Stripe dashboard", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, payment_intent_id: nil))
    generate(payment(course_registration_id: registration.id, amount: registration.amount, payment_intent_id: "pi_123"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")

    assert has_element?(view, ~s|a[href$="/payments/pi_123"]|, "Stripe")
  end

  test "removing a seat frees it but leaves the sale the receipt shows", %{conn: conn} do
    course = generate(course(total_places: 10))

    registration =
      generate(course_registration(course_id: course.id, status: :confirmed, seats: 3, amount: Decimal.new("255.00")))

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

    view |> element(~s|button[phx-click="remove_seat"][phx-value-id="#{registration.id}"]|) |> render_click()

    assert render(view) =~ "2 / 10 seats"
    reloaded = Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false)
    assert reloaded.seats == 3
    assert reloaded.removed_seats == 1
    assert Decimal.equal?(reloaded.amount, "255.00")
  end

  describe "refund" do
    defp paid_booking(payment_opts, registration_opts \\ []) do
      registration =
        generate(
          course_registration([status: :confirmed, name: "Anna", amount: Decimal.new("85.00")] ++ registration_opts)
        )

      generate(payment([course_registration_id: registration.id, amount: Decimal.new("85.00")] ++ payment_opts))
      registration
    end

    defp refund_menu_item(registration), do: "#registration-actions-#{registration.id} button"

    test "Refund is offered only once nothing is to collect", %{conn: conn} do
      unpaid = generate(course_registration(status: :confirmed, name: "Unpaid Ulla"))
      paid = paid_booking([method: :cash], course_id: unpaid.course_id)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{paid.course_id}")

      refute has_element?(view, refund_menu_item(unpaid), "Refund")
      assert has_element?(view, refund_menu_item(paid), "Refund")

      view |> element(refund_menu_item(paid), "Refund") |> render_click()

      assert has_element?(view, "#settlement-drawer #refund-#{paid.id}-form")
    end

    test "a part refund by cash is recorded with its reason and leaves nothing to collect", %{conn: conn} do
      registration = paid_booking(method: :cash)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      view |> element(refund_menu_item(registration), "Refund") |> render_click()

      view
      |> form("#refund-#{registration.id}-form", refund: %{amount: "20", how: "cash", note: "Ran short of moss"})
      |> render_submit()

      assert has_element?(view, "#registration-#{registration.id}", "Refunded €20.00 · Cash")
      assert has_element?(view, "#registration-#{registration.id}", "Ran short of moss")
      refute has_element?(view, "#registration-#{registration.id}", "To collect")
      refute has_element?(view, "#registration-#{registration.id}", "To refund")
      assert [_job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendRefundedEmail)
    end

    test "a part refund by Stripe is sent and recorded, leaving nothing to collect", %{conn: conn} do
      registration = paid_booking(payment_intent_id: "pi_booking")

      Edenflowers.External.StripeAPI.Mock
      |> Mox.stub(:list_refunds, fn "pi_booking" -> {:ok, []} end)
      |> Mox.expect(:create_refund, fn "pi_booking", 2_000, _key, %{"reason" => "refund"} ->
        {:ok, %{id: "re_booking", payment_intent: "pi_booking", amount: 2_000, status: "succeeded"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      view |> element(refund_menu_item(registration), "Refund") |> render_click()

      view
      |> form("#refund-#{registration.id}-form", refund: %{amount: "20.00", how: "stripe"})
      |> render_submit()

      assert has_element?(view, "#registration-#{registration.id}", "Refunded €20.00 · Stripe")
      refute has_element?(view, "#registration-#{registration.id}", "To collect")
      refute has_element?(view, "#registration-#{registration.id}", "To refund")
    end
  end
end

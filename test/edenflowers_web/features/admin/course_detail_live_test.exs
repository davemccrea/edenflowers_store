defmodule EdenflowersWeb.Admin.CourseDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  use Oban.Testing, repo: Edenflowers.Repo

  import Phoenix.LiveViewTest
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses

  setup :log_in_admin

  test "booking notifications keep the course's bookings scoped to that course", %{conn: conn, admin: admin} do
    registration = generate(course_registration(status: :confirmed, seats: 3))
    other = generate(course_registration(status: :confirmed, seats: 3))
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")

    Courses.cancel_registration!(other, %{email_customer?: false}, actor: admin)
    render(view)
    assert has_element?(view, "#registration-#{registration.id}", "+2")
    refute has_element?(view, "#registration-#{other.id}")

    Courses.remove_registration_seat!(registration, actor: admin)
    assert has_element?(view, "#editor-stale-notice")
    assert has_element?(view, "#registration-#{registration.id}", "+2")
    view |> element("#editor-stale-notice button") |> render_click()
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#registration-#{registration.id}", "+1")
  end

  test "removing a seat locally reloads the course", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, seats: 3))
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")

    view |> element(~s|button[phx-click="remove_seat"][phx-value-id="#{registration.id}"]|) |> render_click()

    assert has_element?(view, "#registration-#{registration.id}", "+1")
  end

  test "an open payment drawer keeps its entered values while refusing a second voucher", %{conn: conn, admin: admin} do
    course = generate(course())
    registration = generate(course_registration(course_id: course.id, status: :confirmed))
    first = generate(gift_voucher(amount: Decimal.new(20)))
    second = generate(gift_voucher(amount: Decimal.new(40)))

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")
    view |> element("#settle-#{registration.id}") |> render_click()

    view
    |> form("#payment-#{registration.id}-form", payment: %{payment_method: "voucher"})
    |> render_change(%{"_target" => ["payment", "payment_method"]})

    view
    |> form("#payment-#{registration.id}-form", payment: %{code: second.code})
    |> render_change()

    Edenflowers.Courses.pay_registration_with_gift_voucher!(registration, first.code, actor: admin)
    render(view)

    assert has_element?(view, "#payment-#{registration.id}-code[value='#{second.code}']")

    view |> form("#payment-#{registration.id}-form") |> render_submit()

    assert has_element?(view, "#payment-#{registration.id}-code-error", "Another gift voucher")

    fresh = Ash.reload!(registration, load: [:amount_paid], authorize?: false)
    assert fresh.gift_voucher_id == first.id
    assert Decimal.eq?(fresh.amount_paid, 20)
  end

  test "shows publication status and only offers sharing for published courses", %{conn: conn} do
    for {draft, status} <- [{true, "Draft"}, {false, "Published"}] do
      course = generate(course(draft: draft))
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

      assert has_element?(view, ".badge", status)
      assert has_element?(view, "#share-course-link-url") == !draft
      assert has_element?(view, "#share-course-link-open") == !draft
    end
  end

  test "Jennie previews and manually sends course reminders in each booking's language", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths"))
    anna = generate(course_registration(course_id: course.id, status: :confirmed, name: "Anna", locale: "en-GB"))

    birgitta =
      generate(course_registration(course_id: course.id, status: :confirmed, name: "Birgitta", locale: "sv-FI"))

    generate(course_registration(course_id: course.id, status: :cancelled, name: "Cancelled Carl"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")
    refute_enqueued(worker: Edenflowers.Courses.Workers.SendReminderEmail)

    view |> element("button[phx-click=open_course_reminders]") |> render_click()
    assert has_element?(view, "#reminder-#{anna.id}", "Anna")
    assert has_element?(view, "#reminder-#{birgitta.id}", "Birgitta")
    refute has_element?(view, "#course-reminder-drawer", "Cancelled Carl")
    assert has_element?(view, "#reminder-#{anna.id}-email-preview-toggle", "A reminder about Autumn wreaths")

    # Each reminder is its own email: rewriting Anna's leaves Birgitta's as built.
    view |> form("#course-reminder-form", reminder: %{anna.id => %{edit_email: "true"}}) |> render_change()
    assert has_element?(view, "#reminder-#{anna.id}-email-body", "Hi Anna,")
    refute has_element?(view, "#reminder-#{birgitta.id}-email-editor")

    assert_no_email_sent()

    view
    |> form("#course-reminder-form",
      reminder: %{anna.id => %{edit_email: "true", subject: "Saturday", body: "Bring an apron."}}
    )
    |> render_submit()

    assert render(view) =~ "Course reminders queued."
    jobs = all_enqueued(worker: Edenflowers.Courses.Workers.SendReminderEmail)
    assert length(jobs) == 2

    arguments = Map.new(jobs, &{&1.args["primary_key"]["id"], &1.args["action_arguments"]})
    assert arguments[anna.id] == %{"subject" => "Saturday", "body" => "Bring an apron."}
    assert arguments[birgitta.id] == %{}
  end

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

  test "the share drawer tags the course's shop URL and remembers the tags once copied", %{conn: conn, admin: admin} do
    course = generate(course())

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

    url = EdenflowersWeb.Endpoint.url() <> "/courses/#{course.slug}"
    assert has_element?(view, ~s|#share-course-link-url[value="#{url}"]|)

    view
    |> form("#share-course-link-form", tags: %{source: "Instagram", medium: "", campaign: "Autumn courses"})
    |> render_change()

    tagged = url <> "?utm_source=instagram&utm_campaign=autumn-courses"
    assert has_element?(view, ~s|#share-course-link-url[value="#{tagged}"]|)

    view |> element("#share-course-link-copy") |> render_click()

    assert [{:campaign, "autumn-courses"}, {:source, "instagram"}] ==
             Edenflowers.Marketing.recent_tracking_tags!(actor: admin)
             |> Enum.map(&{&1.parameter, &1.value})
             |> Enum.sort()

    assert has_element?(view, ~s|#share-course-link-campaign-suggestions [phx-click="pick"]|, "autumn-courses")

    view |> element(~s|button[aria-label="Remove autumn-courses from suggestions"]|) |> render_click()

    refute has_element?(view, "#share-course-link-campaign-suggestions")

    assert [{:source, "instagram"}] ==
             Edenflowers.Marketing.recent_tracking_tags!(actor: admin) |> Enum.map(&{&1.parameter, &1.value})
  end

  test "tapping a suggested tag fills it in, and tapping it again clears it", %{conn: conn, admin: admin} do
    course = generate(course())
    Edenflowers.Marketing.use_tracking_tag!(:medium, "email", actor: admin)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")

    url = EdenflowersWeb.Endpoint.url() <> "/courses/#{course.slug}"
    chip = element(view, ~s|#share-course-link-medium-suggestions [phx-click="pick"][phx-value-tag="email"]|)

    render_click(chip)
    assert has_element?(view, ~s|#share-course-link-url[value="#{url}?utm_medium=email"]|)
    assert has_element?(view, ~s|#share-course-link-medium-suggestions button[aria-pressed="true"]|, "email")

    render_click(chip)
    assert has_element?(view, ~s|#share-course-link-url[value="#{url}"]|)
  end

  test "an unknown course goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/courses", flash: %{"error" => "Course not found."}}}} =
             live(conn, ~p"/admin/courses/#{Ecto.UUID.generate()}")
  end

  test "cancelling a booking moves it to the cancelled list", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, name: "Anna"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")

    view |> element(~s|button[phx-click="open_cancel"][phx-value-id="#{registration.id}"]|) |> render_click()
    assert has_element?(view, ~s|#cancel-form input[name="cancel[cancellation_charge]"][value="0"]|)
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

    test "after the course's deadline, prefills the course's fee as the charge", %{
      conn: conn,
      registration: registration
    } do
      Edenflowers.Courses.Course
      |> Ash.get!(registration.course_id, authorize?: false)
      |> Ash.Seed.update!(%{cancellation_fee_percent: 50})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      open_cancel(view, registration)

      assert has_element?(view, ~s|#cancel-form input[name="cancel[cancellation_charge]"][value="42.50"]|)
    end

    test "before the course's deadline, prefills no charge", %{conn: conn, registration: registration} do
      Edenflowers.Courses.Course
      |> Ash.get!(registration.course_id, authorize?: false)
      |> Ash.Seed.update!(%{cancellation_fee_percent: 50, cancellation_days: 2})

      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      open_cancel(view, registration)

      assert has_element?(view, ~s|#cancel-form input[name="cancel[cancellation_charge]"][value="0"]|)
    end

    test "keeps the charge Jennie enters and leaves the rest to hand back", %{conn: conn, registration: registration} do
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      open_cancel(view, registration)

      view
      |> form("#cancel-form", cancel: %{cancellation_charge: "35,00", cancellation_reason: "Ill that day"})
      |> render_submit()

      assert has_element?(view, "#registration-#{registration.id}", "To refund 50,00 €")

      view |> element("#settle-#{registration.id}", "To refund") |> render_click()
      assert has_element?(view, "#settlement-drawer dl", "Cancellation charge")
      assert has_element?(view, "#settlement-drawer dl", "35,00 €")
      assert has_element?(view, "#settlement-drawer", "Ill that day")
      assert has_element?(view, "#settlement-drawer", "Cancellation emailed to #{registration.email}.")

      view |> form("#refund-#{registration.id}-form", refund: %{payment_method: "cash"}) |> render_submit()

      refute has_element?(view, "#registration-#{registration.id}", "To refund")
      registration = Ash.load!(registration, [:amount_paid], authorize?: false, reuse_values?: false)
      assert Decimal.equal?(registration.amount_paid, "35.00")
    end

    test "a charge over the booking's total keeps the drawer open with the error", %{
      conn: conn,
      registration: registration
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")
      open_cancel(view, registration)

      view |> form("#cancel-form", cancel: %{cancellation_charge: "90"}) |> render_submit()

      assert has_element?(view, "#cancel_cancellation_charge-error", "Enter an amount from 0 € to 85,00 €.")
      assert Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false).status == :confirmed
    end
  end

  describe "adding a booking" do
    test "opens a dedicated booking page with its payment choices", %{conn: conn} do
      course = generate(course())
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")
      view |> element(~s|a[href="/admin/courses/#{course.id}/bookings/new"]|) |> render_click()
      assert_redirect(view, ~p"/admin/courses/#{course.id}/bookings/new")
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/bookings/new")

      assert has_element?(view, "#booking-course", course.name)
      assert has_element?(view, "#booking-course", Edenflowers.Format.date(course.date, "en-GB"))
      assert has_element?(view, "#booking-course", course.location_name)
      assert has_element?(view, "#booking-form h2", "Booking details")
      assert has_element?(view, "#booking-form h2", "Payment")
      assert has_element?(view, "#booking-form h2", "Confirmation")
      assert has_element?(view, "#booking-form label", "Email language")
      assert has_element?(view, ~s|input[type="radio"][value="on_fulfillment"][checked]|)
      assert has_element?(view, "#booking-form label", "Payment link")
      assert has_element?(view, "#booking-form label", "In person")
      refute has_element?(view, ~s|input[type="radio"][value="received"]|)
      refute has_element?(view, "#booking-drawer")

      view |> form("#booking-form", form: %{email: "ada@example.com"}) |> render_change()

      assert has_element?(view, "#booking-email-preview-toggle summary", "Preview the email")
      refute has_element?(view, "#booking-email-preview-toggle[open]")
      refute has_element?(view, "#booking-email-preview")
    end

    test "cancel returns to the course without creating a booking", %{conn: conn} do
      course = generate(course())
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/bookings/new")
      view |> element("a", "Cancel") |> render_click()
      assert_redirect(view, ~p"/admin/courses/#{course.id}")
      assert Ash.read!(Edenflowers.Courses.CourseRegistration, authorize?: false) == []
    end

    test "preview keeps browser-controlled disclosure state while its contents update", %{conn: conn} do
      course = generate(course())
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/bookings/new")

      view
      |> form("#booking-form", form: %{email: "ada@example.com", locale: "en-GB"})
      |> render_change()

      [disclosure] =
        view
        |> element("#booking-email-preview-toggle")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("phx-mounted")

      assert Jason.decode!(disclosure) == [["ignore_attrs", %{"attrs" => ["open"]}]]
      assert has_element?(view, "#booking-email-preview-toggle", "You can pay when you come to the course.")

      view
      |> form("#booking-form", form: %{payment_terms: "payment_link"})
      |> render_change()

      assert has_element?(view, "#booking-email-preview-toggle", "You can pay online here:")
      refute has_element?(view, "#booking-email-preview-toggle", "You can pay when you come to the course.")
    end

    test "invalid details leave the form open without creating a booking", %{conn: conn} do
      course = generate(course())
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/bookings/new")
      view |> form("#booking-form", form: %{name: "", email: "invalid"}) |> render_submit()
      assert has_element?(view, "#booking-form")
      assert Ash.read!(Edenflowers.Courses.CourseRegistration, authorize?: false) == []
    end

    test "collects a part payment through the shared settlement form and previews its receipt", %{conn: conn} do
      booking = generate(course_registration(status: :confirmed))
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{booking.course_id}")
      view |> element("#settle-#{booking.id}") |> render_click()

      assert has_element?(view, "#settlement-drawer h3", "Payment link")
      assert has_element?(view, "#settlement-drawer h3", "Record payment")
      assert has_element?(view, "#settlement-drawer dl > div:first-child", "Amount due")
      assert has_element?(view, "#payment-#{booking.id}-form label", "Payment method")
      assert has_element?(view, "#payment-#{booking.id}-form label", "Amount received (€)")

      view
      |> form("#payment-#{booking.id}-form",
        payment: %{amount: "30,00", payment_method: "cash", email_receipt?: "false"}
      )
      |> render_change()

      assert has_element?(view, "#payment-#{booking.id}-form", "Record payment")

      view
      |> form("#payment-#{booking.id}-form",
        payment: %{amount: "30,00", payment_method: "cash", email_receipt?: "false"}
      )
      |> render_submit()

      assert has_element?(view, "#settle-#{booking.id}", "To collect 55,00 €")
      assert [%{method: :cash}] = Ash.load!(booking, :payments, authorize?: false).payments
    end

    defp add_booking(view, course, email_customer?, terms \\ "on_fulfillment") do
      view
      |> form("#booking-form",
        form: %{
          name: "Birgitta",
          email: "birgitta@example.com",
          seats: "2",
          locale: "en-GB",
          email_customer?: email_customer?,
          payment_terms: terms
        }
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin/courses/#{course.id}")

      Ash.read_one!(Edenflowers.Courses.CourseRegistration, authorize?: false)
    end

    test "confirms places and optionally emails without a receipt or automatic payment link", %{conn: conn} do
      course = generate(course(name: "Autumn wreaths", total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/bookings/new")
      assert has_element?(view, "#booking-form", "Email booking confirmation")

      registration = add_booking(view, course, "true")

      assert registration.status == :confirmed
      refute registration.payment_link_token
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")
      refute has_element?(view, "#invites")
      assert has_element?(view, "#bookings li", "Birgitta")
      assert render(view) =~ "2 / 10 seats"

      assert %{success: 1} = Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.to == [{"", "birgitta@example.com"}]
        refute email.text_body =~ "/pay/courses/"
        assert email.text_body =~ "Your 2 places on Autumn wreaths are confirmed."
        assert email.text_body =~ "You can pay when you come to the course."
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
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/bookings/new")

      registration = add_booking(view, course, "false")
      refute registration.payment_link_token
      refute registration.confirmation_emailed_at

      refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
      assert_no_email_sent()
    end

    test "payment-link confirmation previews and sends a link without recording money", %{conn: conn} do
      course = generate(course(total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/bookings/new")

      view
      |> form("#booking-form", form: %{email: "birgitta@example.com", locale: "en-GB", payment_terms: "payment_link"})
      |> render_change()

      assert has_element?(view, "#booking-email-preview-toggle", "You can pay online here:")
      refute has_element?(view, "#booking-email-preview-toggle", "You can pay when you come to the course.")

      booking = add_booking(view, course, "true", "payment_link")
      assert booking.status == :confirmed
      assert booking.payment_terms == :payment_link
      assert booking.payment_link_token
      assert Ash.load!(booking, :payments, authorize?: false).payments == []
      assert %{success: 1} = Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.text_body =~ EdenflowersWeb.PaymentLink.url_for(booking)
        assert email.text_body =~ "confirmed"
        refute email.text_body =~ "You can pay when you come to the course."
        assert email.attachments == []
      end)

      booking = Ash.get!(Edenflowers.Courses.CourseRegistration, booking.id, authorize?: false)
      assert booking.payment_link_emailed_at
      assert booking.confirmation_emailed_at
      refute booking.receipt_emailed_at
    end

    test "offers a payment link or in person, never bank transfer", %{conn: conn} do
      course = generate(course(total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/bookings/new")

      assert has_element?(view, ~s|input[name="form[payment_terms]"][value="payment_link"]|)
      assert has_element?(view, ~s|input[name="form[payment_terms]"][value="on_fulfillment"]|)
      refute has_element?(view, ~s|input[name="form[payment_terms]"][value="invoice"]|)
    end

    test "a payment link is still created when confirmation is not emailed", %{conn: conn} do
      course = generate(course(total_places: 10))
      {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}/bookings/new")
      booking = add_booking(view, course, "false", "payment_link")
      assert booking.payment_link_token
      refute booking.payment_link_emailed_at
      refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
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

  test "the History lists what happened to each booking and its payments, naming the participant", %{
    conn: conn,
    admin: admin
  } do
    registration = generate(course_registration(status: :confirmed, seats: 2, name: "Ada Lovelace"))
    other = generate(course_registration(course_id: registration.course_id, status: :confirmed, name: "Grace Hopper"))

    Courses.remove_registration_seat!(registration, actor: admin)
    Courses.record_registration_payment!(registration, Decimal.new("10.00"), :cash, actor: admin)

    Courses.cancel_registration!(other, %{email_customer?: false, cancellation_reason: "Fell ill"}, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{registration.course_id}")

    assert has_element?(view, "#course-history", "Seat removed · Ada Lovelace")
    assert has_element?(view, "#course-history", "· Cash · Ada Lovelace")
    assert has_element?(view, "#course-history", "Cancelled · Grace Hopper")
    assert has_element?(view, "#course-history", "Fell ill")
  end

  test "a booking's menu links to its receipt only once money is recorded", %{conn: conn} do
    paid = generate(course_registration(status: :confirmed))
    generate(payment(course_registration_id: paid.id, amount: paid.amount))
    unpaid = generate(course_registration(course_id: paid.course_id, status: :confirmed))

    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{paid.course_id}")

    assert has_element?(view, ~s|a[href="/courses/bookings/#{paid.id}/receipt"]|, "View receipt")
    refute has_element?(view, ~s|a[href="/courses/bookings/#{unpaid.id}/receipt"]|)
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
      |> form("#refund-#{registration.id}-form",
        refund: %{amount: "20", payment_method: "cash", note: "Ran short of moss"}
      )
      |> render_submit()

      assert has_element?(view, "#registration-#{registration.id}", "Refunded 20,00 € · Cash")
      assert has_element?(view, "#registration-#{registration.id}", "Ran short of moss")
      refute has_element?(view, "#registration-#{registration.id}", "To collect")
      refute has_element?(view, "#registration-#{registration.id}", "To refund")
      assert [_job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendRefundedEmail)
    end
  end
end

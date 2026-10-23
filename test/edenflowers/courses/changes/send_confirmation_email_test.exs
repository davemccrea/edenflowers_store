defmodule Edenflowers.Courses.Changes.SendConfirmationEmailTest do
  use Edenflowers.DataCase, async: true
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses.Workers.SendConfirmationEmail

  test "a booking awaiting payment gets its payment link instead of a confirmation" do
    registration =
      generate(course_registration(status: :awaiting_payment, payment_link_token: "tok", email: "anna@example.com"))

    assert {:ok, _registration} =
             perform_job(SendConfirmationEmail, %{"primary_key" => %{"id" => registration.id}})

    assert_email_sent(fn email ->
      assert email.to == [{"", "anna@example.com"}]
      assert email.bcc == [{"Jennie", "info+copy@edenflowers.fi"}]
      assert email.subject =~ "Pay for your booking on Course "
      assert email.text_body =~ ~r/Your place on Course \d+ is confirmed once you've paid\./
      assert email.text_body =~ "/pay/courses/tok"
      assert email.attachments == []
    end)

    reloaded = Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false)
    assert reloaded.payment_link_emailed_at
    refute reloaded.receipt_emailed_at
  end

  @tag :typst
  test "a paid booking gets its receipt" do
    registration = generate(course_registration(status: :confirmed, payment_intent_id: nil))

    generate(
      payment(course_registration_id: registration.id, amount: registration.amount, payment_intent_id: "pi_paid")
    )

    assert {:ok, _registration} =
             perform_job(SendConfirmationEmail, %{"primary_key" => %{"id" => registration.id}})

    assert_email_sent(fn email ->
      refute email.text_body =~ "You pay at the course"
      assert [_receipt] = email.attachments
    end)
  end

  test "sent after the course, thanks the customer instead of confirming the place" do
    course = generate(course(date: Date.add(Edenflowers.ShopTime.today(), -1)))
    registration = generate(course_registration(course_id: course.id, status: :confirmed))

    assert {:ok, _registration} =
             perform_job(SendConfirmationEmail, %{"primary_key" => %{"id" => registration.id}})

    assert_email_sent(fn email ->
      refute email.text_body =~ "confirmed"
      refute email.text_body =~ "pay at the course"
      refute email.text_body =~ "cancel"
      refute email.text_body =~ "See you there"
      assert email.subject =~ "Your booking on Course "
      assert email.text_body =~ ~r/Thank you for coming to Course \d+\./
      assert email.text_body =~ "Reply to this email and I'll send you a link to pay online."
    end)
  end

  describe "the cancellation sentence" do
    defp confirmation(amount_paid) do
      registration = %{
        first_name: "Anna",
        email: "anna@example.com",
        locale: "en",
        seats: 1,
        balance: Decimal.new(0),
        amount_paid: Decimal.new(amount_paid),
        course: %{
          name: "Autumn Wreaths",
          date: ~D[2026-11-20],
          start_time: ~T[18:00:00],
          end_time: ~T[20:00:00],
          location_name: "Studio",
          location_address: "Storgatan 1"
        }
      }

      Edenflowers.Email.course_confirmation(registration).text_body
    end

    test "promises a paid booking a full refund 7 days before the course" do
      assert confirmation("85.00") =~ "Let me know at least 7 days before the course for a full refund."
    end

    test "only asks an unpaid booking for notice" do
      body = confirmation("0")

      assert body =~ "Please let me know at least 7 days before the course if you can."
      refute body =~ "refund"
    end
  end
end

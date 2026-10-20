defmodule Edenflowers.Courses.Changes.SendConfirmationEmailTest do
  use Edenflowers.DataCase, async: true
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses.Workers.SendConfirmationEmail

  test "a booking that pays at the course gets a confirmation without a receipt" do
    registration = generate(course_registration(status: :confirmed, email: "anna@example.com"))

    assert {:ok, _registration} =
             perform_job(SendConfirmationEmail, %{"primary_key" => %{"id" => registration.id}})

    assert_email_sent(fn email ->
      assert email.to == [{"", "anna@example.com"}]
      assert email.bcc == [Application.fetch_env!(:edenflowers, :mailer_from_address)]
      assert email.subject =~ "You're booked on Course "
      assert email.text_body =~ ~r/Your place on Course \d+ is confirmed\./
      assert email.text_body =~ "You pay at the course"
      assert email.attachments == []
    end)

    reloaded = Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false)
    assert reloaded.confirmation_emailed_at
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

  describe "a paid booking's cancellation sentence" do
    defp paid_confirmation(fee) do
      registration = %{
        first_name: "Anna",
        email: "anna@example.com",
        locale: "en",
        seats: 1,
        balance: Decimal.new(0),
        course: %{
          name: "Autumn Wreaths",
          date: ~D[2026-11-20],
          start_time: ~T[18:00:00],
          end_time: ~T[20:00:00],
          location_name: "Studio",
          location_address: "Storgatan 1",
          late_cancellation_fee: Decimal.new(fee)
        }
      }

      Edenflowers.Email.course_confirmation(registration, nil).text_body
    end

    test "names the course's late-cancellation fee" do
      assert paid_confirmation("15.00") =~ "If you cancel later, I keep €15.00 as a cancellation fee."
    end

    test "only asks for notice when there is no fee" do
      body = paid_confirmation("0.00")

      assert body =~ "Please let me know at least 7 days before the course if you can."
      refute body =~ "cancellation fee"
    end
  end
end

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
      assert email.text_body =~ ~r/I've kept you a place on Course \d+, and paying confirms it\./
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

  test "a booking still awaiting payment after the course gets a payment reminder, not the link" do
    registration =
      generate(course_registration(status: :awaiting_payment, payment_link_token: "tok", email: "anna@example.com"))

    Edenflowers.Courses.Course
    |> Ash.get!(registration.course_id, authorize?: false)
    |> Ash.Seed.update!(%{date: Date.add(Edenflowers.ShopTime.today(), -1)})

    assert {:ok, _registration} =
             perform_job(SendConfirmationEmail, %{"primary_key" => %{"id" => registration.id}})

    assert_email_sent(fn email ->
      refute email.text_body =~ "kept you a place"
      assert email.subject =~ "A reminder about your booking on"
      assert email.text_body =~ "/pay/courses/tok"
    end)
  end

  defp confirmation_email(amount_paid, date \\ ~D[2026-11-20]) do
    Edenflowers.Email.course_confirmation(%Edenflowers.Courses.CourseRegistration{
      first_name: "Anna",
      email: "anna@example.com",
      locale: "en",
      seats: 1,
      balance: Decimal.new(0),
      amount_paid: Decimal.new(amount_paid),
      course: %{
        name: "Autumn Wreaths",
        date: date,
        start_time: ~T[18:00:00],
        end_time: ~T[20:00:00],
        location_name: "Studio",
        location_address: "Storgatan 1",
        cancellation_days: 10,
        cancellation_fee_percent: 50
      }
    })
  end

  describe "the confirmation" do
    test "names the course and its day in the subject" do
      assert confirmation_email("85.00").subject == "You're booked on Autumn Wreaths, Friday 20.11."
    end

    test "states the course's own cancellation terms" do
      body = confirmation_email("85.00").text_body

      refute body =~ "work something out"

      assert body =~
               "To cancel, reply to this email. Cancel at least 10 days before the course for a full refund. After that, 50% of the price is kept."
    end
  end
end

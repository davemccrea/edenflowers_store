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

  test "sent after the course, thanks the customer instead of confirming the place" do
    email = confirmation_email("85.00", Date.add(Edenflowers.ShopTime.today(), -1))

    refute email.text_body =~ "confirmed"
    refute email.text_body =~ "When:"
    refute email.text_body =~ "cancel"
    refute email.text_body =~ "See you there"
    assert email.subject =~ "Your booking on Autumn Wreaths"
    assert email.text_body =~ "Thank you for coming to Autumn Wreaths."
    assert email.text_body =~ "Your receipt is attached."
  end

  defp confirmation_email(amount_paid, date \\ ~D[2026-11-20]) do
    Edenflowers.Email.course_confirmation(%{
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
        location_address: "Storgatan 1"
      }
    })
  end

  describe "the cancellation sentence" do
    defp confirmation(amount_paid), do: confirmation_email(amount_paid).text_body

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

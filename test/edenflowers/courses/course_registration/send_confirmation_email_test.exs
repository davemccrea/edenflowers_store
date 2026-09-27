defmodule Edenflowers.Courses.CourseRegistration.SendConfirmationEmailTest do
  use Edenflowers.DataCase
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses.CourseRegistration.Workers.SendConfirmationEmail

  test "a booking that pays at the course gets a confirmation without a receipt" do
    registration = generate(course_registration(status: :confirmed, email: "anna@example.com"))

    assert {:ok, _registration} =
             perform_job(SendConfirmationEmail, %{"primary_key" => %{"id" => registration.id}})

    assert_email_sent(fn email ->
      assert email.to == [{"", "anna@example.com"}]
      assert email.bcc == [Application.fetch_env!(:edenflowers, :mailer_from_address)]
      assert email.text_body =~ "You pay at the course"
      assert email.attachments == []
    end)

    reloaded = Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false)
    assert reloaded.confirmation_emailed_at
    refute reloaded.receipt_emailed_at
  end
end

defmodule Edenflowers.Courses.Workers.SendCourseConfirmationEmailTest do
  use Edenflowers.DataCase
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses.Workers.SendCourseConfirmationEmail

  test "a booking that pays at the course gets a confirmation without a receipt" do
    registration = generate(course_registration(status: :confirmed, email: "anna@example.com"))

    assert :ok = perform_job(SendCourseConfirmationEmail, %{"course_registration_id" => registration.id})

    assert_email_sent(fn email ->
      assert email.to == [{"", "anna@example.com"}]
      assert email.bcc == [Application.fetch_env!(:edenflowers, :mailer_from_address)]
      assert email.text_body =~ "You pay at the course"
      assert email.attachments == []
    end)
  end
end

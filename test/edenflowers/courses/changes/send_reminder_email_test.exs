defmodule Edenflowers.Courses.Changes.SendReminderEmailTest do
  use Edenflowers.DataCase, async: true
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Courses.Schedulers.SendReminderEmail, as: ScheduleReminders
  alias Edenflowers.Courses.Workers.SendReminderEmail

  setup do
    today = Edenflowers.ShopTime.today()
    %{tomorrow: generate(course(date: Date.add(today, 1), register_before: today)).id}
  end

  test "bookings on tomorrow's course are reminded once", %{tomorrow: course_id} do
    confirmed = generate(course_registration(course_id: course_id, status: :confirmed, email: "anna@example.com"))

    assert scheduled_reminders() == [confirmed.id]

    assert {:ok, _registration} = perform_job(SendReminderEmail, %{"primary_key" => %{"id" => confirmed.id}})

    assert_email_sent(fn email ->
      refute email.text_body =~ "Amount due"
      assert email.to == [{"", "anna@example.com"}]
      assert email.bcc == [{"Jennie", "info+copy@edenflowers.fi"}]
      assert email.subject =~ ~r/^See you tomorrow at Course \d+$/
      assert email.text_body =~ ~r/A reminder that Course \d+ is tomorrow\./
    end)

    assert Ash.get!(CourseRegistration, confirmed.id, authorize?: false).reminder_emailed_at
    Edenflowers.Repo.delete_all(Oban.Job)
    assert scheduled_reminders() == []
  end

  test "cancelled bookings, unpaid invites and other days' courses get nothing", %{tomorrow: course_id} do
    generate(course_registration(course_id: course_id, status: :cancelled))
    generate(course_registration(course_id: course_id, status: :pending, payment_link_token: "tok"))
    generate(course_registration(status: :confirmed))

    assert scheduled_reminders() == []
  end

  defp scheduled_reminders do
    assert :ok = perform_job(ScheduleReminders, %{})
    for job <- all_enqueued(worker: SendReminderEmail), do: job.args["primary_key"]["id"]
  end
end

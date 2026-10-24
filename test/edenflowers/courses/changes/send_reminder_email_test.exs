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

  test "confirmed and awaiting-payment bookings on tomorrow's course are reminded once", %{tomorrow: course_id} do
    confirmed = generate(course_registration(course_id: course_id, status: :confirmed, amount: Decimal.new(0)))

    awaiting =
      generate(
        course_registration(
          course_id: course_id,
          status: :awaiting_payment,
          payment_link_token: "tok",
          email: "anna@example.com"
        )
      )

    assert Enum.sort(scheduled_reminders()) == Enum.sort([confirmed.id, awaiting.id])

    assert {:ok, _registration} = perform_job(SendReminderEmail, %{"primary_key" => %{"id" => awaiting.id}})

    assert_email_sent(fn email ->
      assert email.to == [{"", "anna@example.com"}]
      assert email.bcc == [{"Jennie", "info+copy@edenflowers.fi"}]
      assert email.subject =~ ~r/^See you tomorrow at Course \d+$/
      assert email.text_body =~ ~r/A reminder that Course \d+ is tomorrow\./
      assert email.text_body =~ "Amount due: €85.00"
      assert email.text_body =~ "/pay/courses/tok"
    end)

    assert {:ok, _registration} = perform_job(SendReminderEmail, %{"primary_key" => %{"id" => confirmed.id}})

    assert_email_sent(fn email -> not (email.text_body =~ "Amount due" or email.text_body =~ "pay online") end)

    assert Ash.get!(CourseRegistration, awaiting.id, authorize?: false).reminder_emailed_at
    Edenflowers.Repo.delete_all(Oban.Job)
    assert scheduled_reminders() == []
  end

  test "cancelled bookings, released holds and other days' courses get nothing", %{tomorrow: course_id} do
    generate(course_registration(course_id: course_id, status: :cancelled))
    generate(course_registration(course_id: course_id, status: :pending))
    generate(course_registration(status: :confirmed))

    assert scheduled_reminders() == []
  end

  defp scheduled_reminders do
    assert :ok = perform_job(ScheduleReminders, %{})
    for job <- all_enqueued(worker: SendReminderEmail), do: job.args["primary_key"]["id"]
  end
end

defmodule Edenflowers.Courses.CourseRegistration.Changes.SendReminderEmailTest do
  use Edenflowers.DataCase, async: true
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Courses.Workers.SendReminderEmail

  test "manual reminders queue only confirmed bookings and preserve Jennie's message" do
    admin = generate(admin_user())
    course = generate(course(date: Date.add(Edenflowers.ShopTime.today(), 5)))
    confirmed = generate(course_registration(course_id: course.id, status: :confirmed, locale: "en-GB"))
    generate(course_registration(course_id: course.id, status: :cancelled))
    generate(course_registration(course_id: course.id, status: :pending))
    generate(course_registration(status: :confirmed))

    refute_enqueued(worker: SendReminderEmail)
    assert {:ok, 1} = Courses.send_course_reminders(course.id, "Bring an apron.", admin)

    assert [%{args: args}] = all_enqueued(worker: SendReminderEmail)
    assert args["primary_key"]["id"] == confirmed.id
    assert args["action_arguments"]["message"] == "Bring an apron."

    assert {:ok, _registration} = perform_job(SendReminderEmail, args)

    assert_email_sent(fn email ->
      assert email.to == [{"", confirmed.email}]
      assert email.subject == "A reminder about #{course.name}"
      assert email.text_body =~ "Bring an apron."
      assert email.text_body =~ "When:"
      assert email.text_body =~ "Where:"
      assert email.text_body =~ "Please pay at the course."
      assert email.attachments == []
    end)

    assert Ash.get!(CourseRegistration, confirmed.id, authorize?: false).reminder_emailed_at
  end

  test "a cancellation after queueing prevents the reminder from being sent" do
    registration = generate(course_registration(status: :cancelled))

    assert {:cancel, :trigger_no_longer_applies} =
             perform_job(SendReminderEmail, %{"primary_key" => %{"id" => registration.id}})

    assert_no_email_sent()
  end

  test "Jennie may explicitly send another reminder, and no daily schedule exists" do
    admin = generate(admin_user())
    registration = generate(course_registration(status: :confirmed, reminder_emailed_at: DateTime.utc_now()))

    trigger = AshOban.Info.oban_trigger(CourseRegistration, :send_reminder_email)
    assert trigger.scheduler_cron == false
    assert {:ok, 1} = Courses.send_course_reminders(registration.course_id, nil, admin)
    assert_enqueued(worker: SendReminderEmail)
  end
end

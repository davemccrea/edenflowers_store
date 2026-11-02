defmodule Edenflowers.Repo.Migrations.RetireAutomaticCourseReminders do
  use Ecto.Migration

  def up do
    execute """
    UPDATE oban_jobs
    SET state = 'cancelled', cancelled_at = now()
    WHERE worker IN (
      'Edenflowers.Courses.Workers.SendReminderEmail',
      'Edenflowers.Courses.Schedulers.SendReminderEmail'
    ) AND state IN ('available', 'scheduled', 'retryable', 'executing')
    """
  end

  # Rolling back must not reactivate reminders Jennie did not request.
  def down, do: :ok
end

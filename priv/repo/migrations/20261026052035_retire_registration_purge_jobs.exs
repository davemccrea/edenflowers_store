defmodule Edenflowers.Repo.Migrations.RetireRegistrationPurgeJobs do
  use Ecto.Migration

  def up do
    execute """
    UPDATE oban_jobs
    SET state = 'cancelled', cancelled_at = now()
    WHERE worker IN (
      'Edenflowers.Courses.Workers.DiscardAbandoned',
      'Edenflowers.Courses.Schedulers.DiscardAbandoned'
    ) AND state IN ('available', 'scheduled', 'retryable', 'executing')
    """
  end

  # Rollback must not re-enable destructive jobs against retained purchases.
  def down, do: :ok
end

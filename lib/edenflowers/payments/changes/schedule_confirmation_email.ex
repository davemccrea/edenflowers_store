defmodule Edenflowers.Payments.Changes.ScheduleConfirmationEmail do
  @moduledoc """
  Enqueues the `:send_confirmation_email` trigger in the confirming transaction,
  so a confirmed order or booking always has its email queued.

  Unlike the built-in `run_oban_trigger`, a failed enqueue becomes an action
  error rather than an exception. `Edenflowers.Payments.complete/1` relies on
  that to report the failure instead of raising.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      try do
        AshOban.run_trigger(record, :send_confirmation_email)
        {:ok, record}
      rescue
        error -> {:error, {:enqueue_failed, record.id, error}}
      end
    end)
  end
end

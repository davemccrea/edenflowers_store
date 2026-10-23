defmodule Edenflowers.Payments.Changes.QueueEmail do
  @moduledoc """
  Enqueues the email trigger named by `:trigger` in the action's transaction,
  so the record always has its email queued, with Jennie's `message` when the
  action takes one, and any other `arguments` the email needs.

  Unlike the built-in `run_oban_trigger`, a failed enqueue becomes an action
  error rather than an exception. `Edenflowers.Payments.complete/1` relies on
  that to report the failure instead of raising.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    # `arguments` names what the email's action takes from this one's, as `[amount: :amount_paid]`.
    action_arguments =
      [message: :message]
      |> Keyword.merge(opts[:arguments] || [])
      |> Map.new(fn {name, from} -> {name, Ash.Changeset.get_argument(changeset, from)} end)
      |> Map.reject(fn {_name, value} -> is_nil(value) end)

    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      try do
        AshOban.run_trigger(record, Keyword.fetch!(opts, :trigger), action_arguments: action_arguments)
        {:ok, record}
      rescue
        error -> {:error, {:enqueue_failed, record.id, error}}
      end
    end)
  end

  # Queuing happens after the update, so it works the same on an atomic one.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end

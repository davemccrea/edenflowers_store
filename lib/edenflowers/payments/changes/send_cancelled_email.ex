defmodule Edenflowers.Payments.Changes.SendCancelledEmail do
  @moduledoc """
  Queues the email telling the customer their order or booking is cancelled
  and what was refunded, in the cancel's own transaction, so it never goes
  out for a cancel that rolled back. Jennie is BCC'd.

  `cancelled_by` (`:customer` or `:shop`) picks how an order's email closes.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments.Workers.SendCancelledEmail

  @impl true
  def change(changeset, opts, _context) do
    email = Ash.Changeset.get_attribute(changeset, :customer_email) || Map.get(changeset.data, :email)

    changeset
    |> Ash.Changeset.force_change_attribute(:cancellation_emailed_to, email)
    |> Ash.Changeset.after_action(fn changeset, record ->
      job = SendCancelledEmail.new_for(record, changeset.context, opts[:cancelled_by])

      with {:ok, _job} <- Oban.insert(job) do
        {:ok, record}
      end
    end)
  end
end

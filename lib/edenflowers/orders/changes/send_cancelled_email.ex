defmodule Edenflowers.Orders.Changes.SendCancelledEmail do
  @moduledoc """
  Queues the email telling the customer their order is cancelled and what was
  refunded, in the cancel's own transaction, so it never goes out for a
  cancel that rolled back. Jennie is BCC'd, which is how she hears of it.

  `cancelled_by` (`:customer` or `:shop`) picks how the email closes.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.Workers.SendCancelledEmail

  @impl true
  def change(changeset, opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(
      :cancellation_emailed_to,
      Ash.Changeset.get_attribute(changeset, :customer_email)
    )
    |> Ash.Changeset.after_action(fn changeset, order ->
      job = SendCancelledEmail.new_for(order, changeset.context, opts[:cancelled_by])

      with {:ok, _job} <- Oban.insert(job) do
        {:ok, order}
      end
    end)
  end
end

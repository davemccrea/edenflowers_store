defmodule Edenflowers.Orders.Changes.SendCancelledEmail do
  @moduledoc """
  Queues the email telling the customer their order is cancelled and what was
  refunded, in the cancel's own transaction. Jennie is BCC'd, which is how she
  hears of it.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.Workers.SendCancelledEmail

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      with {:ok, _job} <- order |> SendCancelledEmail.new_for(changeset.context.refunded_amount) |> Oban.insert() do
        {:ok, order}
      end
    end)
  end
end

defmodule Edenflowers.Payments.Changes.SendRefundedEmail do
  @moduledoc """
  Queues the email telling the customer what Jennie refunded, in the refund's
  own transaction. Nothing is sent to an order with no email address.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments.Workers.SendRefundedEmail

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, record ->
      if Ash.load!(record, :customer_email, authorize?: false).customer_email,
        do: queue_email(record, changeset.arguments),
        else: {:ok, record}
    end)
  end

  defp queue_email(record, arguments) do
    with {:ok, _job} <- record |> SendRefundedEmail.new_for(arguments) |> Oban.insert() do
      {:ok, record}
    end
  end
end

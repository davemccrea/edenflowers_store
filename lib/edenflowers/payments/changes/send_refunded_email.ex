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
      if customer_email(record) do
        with {:ok, _job} <- record |> SendRefundedEmail.new_for(changeset.arguments) |> Oban.insert() do
          {:ok, record}
        end
      else
        {:ok, record}
      end
    end)
  end

  defp customer_email(%Edenflowers.Orders.Order{customer_email: email}), do: email
  defp customer_email(%{email: email}), do: email
end

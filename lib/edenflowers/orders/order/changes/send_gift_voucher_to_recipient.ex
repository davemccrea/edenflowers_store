defmodule Edenflowers.Orders.Order.Changes.SendGiftVoucherToRecipient do
  @moduledoc """
  Emails a Gift voucher sale's voucher PDF to its recipient, at the `to`
  argument, without the receipt. A failed send fails the action, so its job
  retries, and the log records where it went.
  """
  use Ash.Resource.Change

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Order.Changes.SendReceiptEmail

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = SendReceiptEmail.load_for_send(changeset.data)
      to = Ash.Changeset.get_argument(changeset, :to)

      with {:ok, email} <- SendReceiptEmail.with_voucher(Email.gift_voucher_received(order, to), order),
           {:ok, _result} <- Mailer.deliver(email) do
        Ash.Changeset.set_context(changeset, %{paper_trail_metadata: %{email_to: to}})
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to email the gift voucher: #{inspect(error)}")
      end
    end)
  end
end

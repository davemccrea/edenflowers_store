defmodule Edenflowers.Orders.Changes.SendOrderDetailsEmail do
  @moduledoc """
  Emails the order as it stands, with its payment link when one is open: as
  Order details when Jennie places a custom order (`email: :order_details`),
  Order updated after she edits one (`:order_updated`), or Subscription
  payment failed for an Occurrence whose card was refused
  (`:subscription_payment_failed`).
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      # Read fresh: the admin page's copy can predate a payment, and the
      # email says what's owed.
      order =
        Ash.get!(
          Edenflowers.Orders.Order,
          changeset.data.id,
          load: [
            :customer_first_name,
            :grand_total,
            :amount_paid,
            :balance,
            :payment_link_open?,
            line_items: [:subtotal]
          ],
          authorize?: false
        )

      deliver(changeset, order, Keyword.fetch!(opts, :email))
    end)
  end

  defp deliver(changeset, order, kind) do
    message = Ash.Changeset.get_argument(changeset, :message)

    case order |> email(kind, payment_link_url(order), message) |> Mailer.deliver() do
      {:ok, _result} ->
        Logger.info("Sent #{kind} email for order #{order.id}")

        changeset
        |> Ash.Changeset.force_change_attribute(:order_details_emailed_at, DateTime.utc_now())
        |> Ash.Changeset.set_context(%{paper_trail_metadata: %{email_message: message}})
        |> clear_failure()

      {:error, error} ->
        Ash.Changeset.add_error(changeset, "Failed to send #{kind} email: #{inspect(error)}")
    end
  end

  defp email(order, :order_details, url, message), do: Email.order_details(order, url, message)
  defp email(order, :order_updated, url, message), do: Email.order_updated(order, url, message)
  defp email(order, :subscription_payment_failed, url, _message), do: Email.subscription_payment_failed(order, url)

  defp payment_link_url(%{payment_link_open?: true} = order), do: EdenflowersWeb.PaymentLink.url_for(order)
  defp payment_link_url(_order), do: nil

  # Atomic, so a caller holding a copy from before the failure still clears it.
  defp clear_failure(changeset), do: Ash.Changeset.atomic_update(changeset, :order_details_email_failed_at, nil)
end

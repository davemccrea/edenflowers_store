defmodule Edenflowers.Orders.Changes.SendOrderDetailsEmail do
  @moduledoc """
  Emails the order as it stands, with its payment link when one is open: as
  Order details when Jennie places a custom order (`email: :order_details`),
  Order updated after she edits one (`:order_updated`), Subscription
  payment failed for an Occurrence whose card was refused
  (`:subscription_payment_failed`), or the Payment reminder she sends by
  hand (`:payment_reminder`).
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
            :payable?,
            line_items: [:subtotal]
          ],
          authorize?: false
        )

      case Keyword.fetch!(opts, :email) do
        :payment_reminder when not order.payable? -> Ash.Changeset.add_error(changeset, "has nothing to pay")
        kind -> deliver(changeset, order, kind)
      end
    end)
  end

  defp deliver(changeset, order, kind) do
    message = Ash.Changeset.get_argument(changeset, :message)

    case order |> email(kind, payment_link_url(changeset, order, kind), message) |> Mailer.deliver() do
      {:ok, _result} ->
        Logger.info("Sent #{kind} email for order #{order.id}")

        changeset
        |> stamp(kind)
        |> Ash.Changeset.set_context(%{paper_trail_metadata: %{email_message: message}})
        |> clear_failure()

      {:error, error} ->
        Ash.Changeset.add_error(changeset, "Failed to send #{kind} email: #{inspect(error)}")
    end
  end

  defp email(order, :order_details, url, message), do: Email.order_details(order, url, message)
  defp email(order, :order_updated, url, message), do: Email.order_updated(order, url, message)
  defp email(order, :subscription_payment_failed, url, _message), do: Email.subscription_payment_failed(order, url)
  defp email(order, :payment_reminder, url, message), do: Email.payment_reminder(order, url, message)

  # A reminder isn't the order's details, so the menu still offers to send them.
  defp stamp(changeset, :payment_reminder), do: changeset

  defp stamp(changeset, _kind),
    do: Ash.Changeset.force_change_attribute(changeset, :order_details_emailed_at, DateTime.utc_now())

  # A reminder's link may have been opened by this action, so it isn't in the order read above yet.
  defp payment_link_url(changeset, order, :payment_reminder) do
    EdenflowersWeb.PaymentLink.url_for(%{
      order
      | payment_link_token: Ash.Changeset.get_attribute(changeset, :payment_link_token)
    })
  end

  defp payment_link_url(_changeset, %{payment_link_open?: true} = order, _kind),
    do: EdenflowersWeb.PaymentLink.url_for(order)

  defp payment_link_url(_changeset, _order, _kind), do: nil

  # Atomic, so a caller holding a copy from before the failure still clears it.
  defp clear_failure(changeset), do: Ash.Changeset.atomic_update(changeset, :order_details_email_failed_at, nil)
end

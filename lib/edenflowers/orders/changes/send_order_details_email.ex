defmodule Edenflowers.Orders.Changes.SendOrderDetailsEmail do
  @moduledoc """
  Emails the details of an order Jennie entered or edited, including a payment link when one is open.
  Once handed over, the details are a bill, and only worth sending with a link to pay it: an invoice
  order without one gets Jennie's invoice instead.
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      # Read fresh: the admin page's copy can predate the first details email,
      # which goes out in the background, and the wording depends on it.
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

      if order.fulfillment_status == :fulfilled and not order.payment_link_open?,
        do: Ash.Changeset.add_error(changeset, "was handed over and has no payment link"),
        else: deliver(changeset, order)
    end)
  end

  defp deliver(changeset, order) do
    message = Ash.Changeset.get_argument(changeset, :message)

    case order |> Email.order_details(payment_link_url(order), message) |> Mailer.deliver() do
      {:ok, _result} ->
        Logger.info("Sent order details email for order #{order.id}")

        changeset
        |> Ash.Changeset.force_change_attribute(:order_details_emailed_at, DateTime.utc_now())
        |> Ash.Changeset.set_context(%{paper_trail_metadata: %{email_message: message}})
        |> clear_failure()

      {:error, error} ->
        Ash.Changeset.add_error(changeset, "Failed to send order details email: #{inspect(error)}")
    end
  end

  defp payment_link_url(%{payment_link_open?: true} = order), do: EdenflowersWeb.PaymentLink.url_for(order)
  defp payment_link_url(_order), do: nil

  # Atomic, so a caller holding a copy from before the failure still clears it.
  defp clear_failure(changeset), do: Ash.Changeset.atomic_update(changeset, :order_details_email_failed_at, nil)
end

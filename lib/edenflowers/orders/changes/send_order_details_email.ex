defmodule Edenflowers.Orders.Changes.SendOrderDetailsEmail do
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order =
        Ash.load!(changeset.data, [:customer_first_name, :grand_total, line_items: [:subtotal]], authorize?: false)

      case order |> Email.order_details(payment_link_url(order)) |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent order details email for order #{order.id}")
          Ash.Changeset.force_change_attribute(changeset, :details_emailed_at, DateTime.utc_now())

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send order details email: #{inspect(error)}")
      end
    end)
  end

  defp payment_link_url(%{payment_link_token: nil}), do: nil
  defp payment_link_url(%{payment_status: :paid}), do: nil
  defp payment_link_url(order), do: EdenflowersWeb.PaymentLink.url_for(order)
end

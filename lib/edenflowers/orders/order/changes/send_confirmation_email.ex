defmodule Edenflowers.Orders.Order.Changes.SendConfirmationEmail do
  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Receipt

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = load_for_send(changeset.data)

      with {:ok, pdf} <- Receipt.generate(order),
           {:ok, _result} <- order |> build_email(pdf) |> Mailer.deliver() do
        Logger.info("Sent confirmation email for order #{order.id}")

        changeset
        |> Ash.Changeset.force_change_attribute(:receipt_emailed_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:receipt_sha256, sha256_hex(pdf))
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send confirmation email: #{inspect(error)}")
      end
    end)
  end

  defp build_email(order, pdf) do
    attachment =
      Swoosh.Attachment.new(
        {:data, pdf},
        filename: "eden-flowers-#{order.order_reference}.pdf",
        content_type: "application/pdf"
      )

    order
    |> Email.order_confirmation()
    |> Swoosh.Email.attachment(attachment)
  end

  defp sha256_hex(bytes) do
    :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end

  defp load_for_send(order) do
    Ash.load!(
      order,
      [
        :customer_first_name,
        :items_subtotal,
        :items_total,
        :discount,
        :promotion_applied?,
        :grand_total,
        :vat,
        line_items: [:subtotal, :total, :unit_price_ex_tax]
      ],
      actor: system_actor(),
      authorize?: false
    )
  end
end

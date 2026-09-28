defmodule Edenflowers.Orders.Changes.SendConfirmationEmail do
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
           {:ok, _result} <-
             order
             |> Email.order_confirmation()
             |> Swoosh.Email.attachment(Receipt.attachment(pdf, order.order_reference))
             |> Mailer.deliver() do
        Logger.info("Sent confirmation email for order #{order.id}")

        changeset
        |> Ash.Changeset.force_change_attribute(:receipt_emailed_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:receipt_sha256, Receipt.sha256(pdf))
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send confirmation email: #{inspect(error)}")
      end
    end)
  end

  defp load_for_send(order) do
    Ash.load!(order, [:customer_first_name, :vat | Receipt.order_load()], actor: system_actor(), authorize?: false)
  end
end

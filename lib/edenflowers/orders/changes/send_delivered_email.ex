defmodule Edenflowers.Orders.Changes.SendDeliveredEmail do
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = Ash.load!(changeset.data, [:customer_first_name, :recipient_first_name], authorize?: false)

      case order |> Email.order_delivered() |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent delivered email for order #{order.id}")
          Ash.Changeset.force_change_attribute(changeset, :delivered_emailed_at, DateTime.utc_now())

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send delivered email: #{inspect(error)}")
      end
    end)
  end
end

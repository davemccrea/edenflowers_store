defmodule Edenflowers.Orders.Changes.SendPaymentFailedEmail do
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = Ash.load!(changeset.data, [:customer_first_name, :grand_total], Ash.Context.to_opts(context))

      case order |> Email.payment_failed(EdenflowersWeb.PaymentLink.url_for(order)) |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent payment failed email for order #{order.id}")
          # The payment link went out with it, as with a custom order's details.
          Ash.Changeset.force_change_attribute(changeset, :details_emailed_at, DateTime.utc_now())

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send payment failed email: #{inspect(error)}")
      end
    end)
  end
end

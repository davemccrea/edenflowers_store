defmodule Edenflowers.Orders.Changes.SendSubscriptionCancelledEmail do
  @moduledoc """
  Emails the customer that Jennie cancelled their subscription, with her
  message and the already-charged delivery that still comes, if there is one.
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      subscription = load_for_send(changeset.data)
      message = Ash.Changeset.get_argument(changeset, :message)

      case subscription |> Email.subscription_cancelled(charged_on(subscription), message) |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent cancelled email for subscription #{subscription.id}")
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send subscription cancelled email: #{inspect(error)}")
      end
    end)
  end

  @doc "Loads what `Email.subscription_cancelled/3` needs, with the product in the customer's language."
  def load_for_send(subscription) do
    subscription
    |> Ash.load!([:fulfillment_option, product_variant: :product, user: [:first_name]], authorize?: false)
    |> then(fn subscription ->
      update_in(
        subscription.product_variant.product,
        &Edenflowers.Translations.translate(&1, String.to_existing_atom(subscription.locale))
      )
    end)
  end

  @doc """
  The day of the delivery already charged that cancelling left in place,
  since it's past the change deadline, or nil.
  """
  def charged_on(subscription) do
    require Ash.Query

    Edenflowers.Orders.Order
    |> Ash.Query.filter(
      subscription_id == ^subscription.id and state == :placed and fulfillment_status == :pending and
        fulfillment_date >= ^Edenflowers.ShopTime.today()
    )
    |> Ash.Query.sort(fulfillment_date: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> nil
      order -> order.fulfillment_date
    end
  end
end

defmodule Edenflowers.Orders.Changes.SendSubscriptionCancelledEmail do
  @moduledoc """
  Emails the customer that their subscription is cancelled, naming the
  already-charged delivery that still comes, if there is one: Subscription
  cancelled with Jennie's message when she cancelled it (`email: :cancelled`),
  or the matter-of-fact confirmation when they did (`:cancellation_confirmed`).
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      subscription = load_for_send(changeset.data)
      message = Ash.Changeset.get_argument(changeset, :message)

      case subscription |> email(opts[:email], message) |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent cancelled email for subscription #{subscription.id}")
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send subscription cancelled email: #{inspect(error)}")
      end
    end)
  end

  defp email(subscription, :cancelled, message),
    do: Email.subscription_cancelled(subscription, charged_on(subscription), message)

  defp email(subscription, :cancellation_confirmed, _message),
    do: Email.subscription_cancellation_confirmed(subscription, charged_on(subscription))

  @doc "Loads what `Email.subscription_cancelled/3` needs, with the product in the customer's language."
  def load_for_send(subscription) do
    subscription
    |> Ash.load!([:fulfillment_option, product_variant: :product, user: [:first_name]], authorize?: false)
    |> Edenflowers.Translations.in_own_locale()
  end

  @doc """
  The day of the delivery already charged that cancelling left in place,
  since it's past the change deadline, or nil.
  """
  def charged_on(subscription) do
    require Ash.Query

    order =
      Edenflowers.Orders.Order
      |> Ash.Query.filter(
        subscription_id == ^subscription.id and state == :placed and fulfillment_status == :pending and
          fulfillment_date >= ^Edenflowers.ShopTime.today()
      )
      |> Ash.Query.sort(fulfillment_date: :asc)
      |> Ash.Query.limit(1)
      |> Ash.read_one!(authorize?: false)

    order && order.fulfillment_date
  end
end

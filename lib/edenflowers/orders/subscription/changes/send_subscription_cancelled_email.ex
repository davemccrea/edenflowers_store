defmodule Edenflowers.Orders.Subscription.Changes.SendSubscriptionCancelledEmail do
  @moduledoc """
  Emails the customer that their subscription is cancelled, naming the
  delivery past its change deadline that still comes, if there is one: Subscription
  cancelled, as Jennie rewrote it if she did, when she cancelled it (`email: :cancelled`),
  or the matter-of-fact confirmation when they did (`:cancellation_confirmed`).
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      subscription = load_for_send(changeset.data)

      case subscription |> email(opts[:email]) |> Edits.apply_to(Edits.from_changeset(changeset)) |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent cancelled email for subscription #{subscription.id}")
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send subscription cancelled email: #{inspect(error)}")
      end
    end)
  end

  defp email(subscription, :cancelled),
    do: Email.subscription_cancelled(subscription, charged_on(subscription))

  defp email(subscription, :cancellation_confirmed),
    do: Email.subscription_cancellation_confirmed(subscription, charged_on(subscription))

  @doc "Loads what `Email.subscription_cancelled/2` needs, with the product in the customer's language."
  def load_for_send(subscription) do
    subscription
    |> Ash.load!([:fulfillment_option, product_variant: :product, user: [:first_name]], authorize?: false)
    |> Edenflowers.Translations.in_own_locale()
  end

  @doc """
  The day of the delivery that cancelling leaves in place,
  since it's past the change deadline, or nil.
  """
  def charged_on(subscription) do
    Ash.load!(subscription, :final_delivery_date, authorize?: false).final_delivery_date
  end
end

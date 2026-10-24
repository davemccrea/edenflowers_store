defmodule Edenflowers.Orders.Changes.SendSubscriptionHeadsUpEmail do
  @moduledoc """
  Tells the customer their next delivery or pickup is coming while they can
  still change it, and stamps which delivery it was about.
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      subscription =
        changeset.data
        |> Ash.load!(
          [:first_order_fulfillment_fee, :fulfillment_option, :user, product_variant: :product],
          Ash.Context.to_opts(context)
        )
        |> translate_product()

      case subscription |> Email.subscription_heads_up() |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent heads-up email for subscription #{subscription.id}")
          Ash.Changeset.force_change_attribute(changeset, :heads_up_emailed_for, subscription.next_fulfillment_date)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send subscription heads-up email: #{inspect(error)}")
      end
    end)
  end

  defp translate_product(subscription) do
    locale = String.to_existing_atom(subscription.locale)
    update_in(subscription.product_variant.product, &Translations.translate(&1, locale))
  end
end

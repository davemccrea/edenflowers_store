defmodule Edenflowers.Orders.Changes.SendSubscriptionSetupEmail do
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      subscription =
        Ash.load!(
          changeset.data,
          [
            :first_order_discounted?,
            :first_delivery_date,
            :first_order_fulfillment_fee,
            :fulfillment_option,
            product_variant: :product,
            user: [:first_name]
          ],
          Ash.Context.to_opts(context)
        )
        |> translate_product()

      case subscription |> Email.subscription_set_up() |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent set-up email for subscription #{subscription.id}")
          Ash.Changeset.force_change_attribute(changeset, :setup_emailed_at, DateTime.utc_now())

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send subscription set-up email: #{inspect(error)}")
      end
    end)
  end

  defp translate_product(subscription) do
    locale = String.to_existing_atom(subscription.locale)
    update_in(subscription.product_variant.product, &Translations.translate(&1, locale))
  end
end

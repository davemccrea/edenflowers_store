defmodule Edenflowers.Orders.Validations.SubscriptionChangesOpen do
  @moduledoc """
  Refuses a customer's change once the next Occurrence is close to being
  created and charged (see `Subscription.changes_closed?`), so a change always
  lands before the card is. Jennie can still make it.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(_changeset, _opts, %{actor: %{admin: true}}), do: :ok

  def validate(changeset, _opts, context) do
    if Ash.load!(changeset.data, :changes_closed?, Ash.Context.to_opts(context)).changes_closed? do
      {:error, field: :next_fulfillment_date, message: ~t"It's too late to change your next delivery."}
    else
      :ok
    end
  end
end

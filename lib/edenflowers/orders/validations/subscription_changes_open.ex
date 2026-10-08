defmodule Edenflowers.Orders.Validations.SubscriptionChangesOpen do
  @moduledoc """
  Refuses a customer's change once the next Occurrence is close to being
  created and charged (see `Subscription.changes_closed?`), so a change always
  lands before the card is. Jennie can still make it.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(_changeset, _opts, %{actor: %{admin: true}}), do: :ok

  def validate(changeset, _opts, context) do
    if Ash.load!(changeset.data, :changes_closed?, Ash.Context.to_opts(context)).changes_closed? do
      {:error, field: :next_fulfillment_date, message: ~t"It's too late to change your next delivery."}
    else
      :ok
    end
  end

  @impl true
  def atomic(_changeset, _opts, %{actor: %{admin: true}}), do: :ok

  def atomic(_changeset, _opts, _context) do
    {:atomic, [:state, :next_fulfillment_date], expr(changes_closed?),
     expr(
       error(^InvalidAttribute, %{
         field: :next_fulfillment_date,
         value: next_fulfillment_date,
         message: ^~t"It's too late to change your next delivery."
       })
     )}
  end
end

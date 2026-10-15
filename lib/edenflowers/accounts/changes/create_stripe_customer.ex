defmodule Edenflowers.Accounts.Changes.CreateStripeCustomer do
  @moduledoc """
  Gives the user a Stripe Customer, unless they already have one.

  Runs after `get_and_lock_for_update`, so two checkouts open at once can't
  each create a Customer: the second waits for the first and sees its id.
  """

  use Ash.Resource.Change

  alias Edenflowers.External.StripeAPI

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn
      %{data: %{stripe_customer_id: customer_id}} = changeset when is_binary(customer_id) ->
        changeset

      changeset ->
        user = changeset.data

        case StripeAPI.impl().create_customer(%{email: to_string(user.email), name: user.name}) do
          {:ok, customer} ->
            Ash.Changeset.force_change_attribute(changeset, :stripe_customer_id, customer.id)

          {:error, reason} ->
            Ash.Changeset.add_error(changeset, "Could not create Stripe Customer: #{inspect(reason)}")
        end
    end)
  end
end

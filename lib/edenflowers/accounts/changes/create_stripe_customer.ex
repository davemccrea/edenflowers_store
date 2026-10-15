defmodule Edenflowers.Accounts.Changes.CreateStripeCustomer do
  @moduledoc "Gives the user a Stripe Customer, unless they already have one."

  use Ash.Resource.Change

  alias Edenflowers.External.StripeAPI

  @impl true
  def change(%{data: %{stripe_customer_id: customer_id}} = changeset, _opts, _context) when is_binary(customer_id),
    do: changeset

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
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

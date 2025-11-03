defmodule Edenflowers.Store.Order.UpsertUserAndAssignToOrder do
  @moduledoc """
  Creates or updates a user and assigns them to the order.

  This change finds or creates a user based on the customer_email
  and customer_name provided in the order. If the user already exists,
  their name is updated. The user is then associated with the order
  via the user_id field.

  If user creation fails, an error is added to the changeset.
  """
  use Ash.Resource.Change
  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Accounts.User

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      customer_email = Ash.Changeset.get_argument_or_attribute(changeset, :customer_email)
      customer_name = Ash.Changeset.get_argument_or_attribute(changeset, :customer_name)

      case User.upsert(customer_email, customer_name, actor: system_actor()) do
        {:ok, user} ->
          Ash.Changeset.force_change_attributes(changeset, user_id: user.id)

        {:error, error} ->
          Logger.info("Failed to upsert user for order: #{inspect(error)}")

          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidChanges{
            message: "Unable to create or update user account"
          })
      end
    end)
  end
end

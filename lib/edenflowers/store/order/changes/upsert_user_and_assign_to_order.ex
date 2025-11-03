defmodule Edenflowers.Store.Order.UpsertUserAndAssignToOrder do
  use Ash.Resource.Change
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

        {:error, _error} ->
          changeset
      end
    end)
  end
end

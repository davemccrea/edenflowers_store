defmodule Edenflowers.Courses.CourseRegistration.Changes.UpsertUser do
  @moduledoc """
  Links the registration to the user with its email, creating one if needed,
  as orders do. A guest booking then shows on the account page once that
  email signs in.
  """
  use Ash.Resource.Change
  import Edenflowers.Actors

  alias Edenflowers.Accounts

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      email = Ash.Changeset.get_attribute(changeset, :email)
      name = Ash.Changeset.get_attribute(changeset, :name)

      case Accounts.upsert_user(email, name, actor: system_actor()) do
        {:ok, user} -> Ash.Changeset.force_change_attribute(changeset, :user_id, user.id)
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end

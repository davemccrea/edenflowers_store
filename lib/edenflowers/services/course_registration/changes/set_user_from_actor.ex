defmodule Edenflowers.Services.CourseRegistration.Changes.SetUserFromActor do
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, %{actor: %{id: user_id}}) do
    Ash.Changeset.force_change_attribute(changeset, :user_id, user_id)
  end

  def change(changeset, _opts, _context), do: changeset
end

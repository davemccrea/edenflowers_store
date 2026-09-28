defmodule Edenflowers.Chat.ActorPersister do
  use AshOban.ActorPersister

  def store(%Edenflowers.Accounts.User{id: id}), do: %{"type" => "user", "id" => id}

  def lookup(%{"type" => "user", "id" => id}) do
    with {:ok, user} <- Ash.get(Edenflowers.Accounts.User, id, authorize?: false) do
      {:ok, Ash.Resource.set_metadata(user, %{chat_agent?: true})}
    end
  end

  def lookup(nil), do: {:ok, nil}
end

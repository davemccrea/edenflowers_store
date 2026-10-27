defmodule EdenflowersWeb.Presence do
  @moduledoc """
  Ephemeral store connections, grouped by signed-in customer or anonymous browser.
  No browsing paths, payment tokens, or connection history are retained.
  """

  use Phoenix.Presence,
    otp_app: :edenflowers,
    pubsub_server: Edenflowers.PubSub

  @topic "store:presence"

  def subscribe, do: Phoenix.PubSub.subscribe(Edenflowers.PubSub, @topic)

  def track_customer(%{admin: true}, _visitor_id), do: :ok

  def track_customer(user, visitor_id) do
    {key, name, user_id} =
      case user do
        nil -> {"visitor:#{visitor_id}", nil, nil}
        user -> {"customer:#{user.id}", user.name || to_string(user.email), user.id}
      end

    track(self(), @topic, key, %{name: name, user_id: user_id})
  end

  def connected_customers do
    @topic
    |> list()
    |> Enum.map(fn {key, %{metas: [meta | _]}} ->
      %{key: key, name: meta.name, user_id: meta.user_id}
    end)
    |> Enum.sort_by(&{&1.name || "", &1.key})
  end
end

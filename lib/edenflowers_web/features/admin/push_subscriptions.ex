defmodule EdenflowersWeb.Admin.PushSubscriptions do
  @moduledoc """
  Server side of the order notifications switch (account page) and offer card
  (Overview). The browser holds the subscription; the reply tells the hook
  whether the server kept it.
  """
  alias Edenflowers.Accounts

  def subscribe(%{"endpoint" => endpoint, "keys" => %{"p256dh" => p256dh, "auth" => auth}}, user)
      when is_binary(endpoint) and is_binary(p256dh) and is_binary(auth) do
    locale = to_string(Localize.get_locale().cldr_locale_id)

    case Accounts.subscribe_to_push(endpoint, p256dh, auth, locale, actor: user) do
      {:ok, _subscription} -> %{ok: true}
      {:error, _error} -> %{ok: false}
    end
  end

  def subscribe(_params, _user), do: %{ok: false}

  def unsubscribe(%{"endpoint" => endpoint}, user) when is_binary(endpoint) do
    with {:ok, subscription} <- Accounts.get_push_subscription(endpoint, actor: user) do
      Accounts.unsubscribe_from_push(subscription, actor: user)
    end

    %{ok: true}
  end

  def unsubscribe(_params, _user), do: %{ok: false}
end

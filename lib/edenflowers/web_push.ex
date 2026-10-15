defmodule Edenflowers.WebPush do
  @moduledoc """
  Sends Web Push messages to a browser's push service. `WebPushEx` encrypts
  the payload (`aes128gcm`, which Apple requires) and signs the VAPID token;
  this posts it with Req.

  Unconfigured (no VAPID keys, as on staging and most dev machines), nothing is
  sent and the admin hides the notifications setting.
  """

  # How long the push service holds a message for a phone that's offline. A
  # new order is still worth hearing about the next morning.
  @ttl_seconds 24 * 60 * 60

  def configured?, do: config() != nil

  def public_key, do: config()[:public_key]

  @doc "A new VAPID key pair, base64url-encoded for `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`."
  def generate_keys do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :prime256v1)

    %{
      public_key: Base.url_encode64(public_key, padding: false),
      private_key: Base.url_encode64(private_key, padding: false)
    }
  end

  @doc """
  Encrypts `payload` for `subscription` and posts it to its push service.

  Returns `{:error, :gone}` when the push service no longer knows the
  subscription (the app was removed or permission revoked), so the caller can
  forget it.
  """
  def deliver(%{endpoint: endpoint, p256dh: p256dh, auth: auth}, payload) when is_binary(payload) do
    subscription = %WebPushEx.Subscription{endpoint: URI.parse(endpoint), keys: %{p256dh: p256dh, auth: auth}}
    request = WebPushEx.request(subscription, payload)

    # Req sets the length itself.
    headers =
      request.headers
      |> Map.delete("Content-Length")
      |> Map.merge(%{"TTL" => to_string(@ttl_seconds), "Urgency" => "high"})

    case Req.post([url: endpoint, body: request.body, headers: headers, retry: false] ++ req_options()) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} when status in [404, 410] -> {:error, :gone}
      {:ok, %{status: status, body: body}} -> {:error, {:push_service, status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp config, do: Application.get_env(:web_push_ex, :vapid)

  defp req_options, do: Application.get_env(:edenflowers, :web_push_req_options, [])
end

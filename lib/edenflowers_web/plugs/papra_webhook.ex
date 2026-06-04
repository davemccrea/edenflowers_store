defmodule EdenflowersWeb.Plugs.PapraWebhook do
  @moduledoc """
  Verifies and dispatches Papra webhook deliveries.

  Mounted in `EdenflowersWeb.Endpoint` *before* `Plug.Parsers` so the raw
  request body is intact for HMAC-SHA256 signature verification — mirroring
  the placement of `Stripe.WebhookPlug`. Only requests whose path matches the
  `:at` option are handled; everything else passes through untouched.

  ## Signature scheme (Standard Webhooks)

  Papra signs webhooks per the Standard Webhooks spec. The signed content is
  `"<webhook-id>.<webhook-timestamp>.<raw-body>"` and the HMAC-SHA256 digest
  is base64-encoded, sent in the `webhook-signature` header as `"v1,<digest>"`.
  The secret being unset (`nil`) fails closed — every delivery is rejected.
  """
  import Plug.Conn
  require Logger

  def init(opts) do
    %{
      path_info: opts |> Keyword.fetch!(:at) |> String.split("/", trim: true),
      handler: Keyword.fetch!(opts, :handler),
      secret: Keyword.fetch!(opts, :secret)
    }
  end

  def call(%Plug.Conn{path_info: path_info} = conn, %{path_info: path_info} = opts) do
    with {:ok, raw_body, conn} <- read_body(conn),
         :ok <- verify_signature(conn, raw_body, resolve(opts.secret)),
         {:ok, payload} <- Jason.decode(raw_body) do
      dispatch(conn, payload, opts.handler)
    else
      {:error, :invalid_signature} ->
        Logger.warning("Rejected Papra webhook: invalid signature")
        conn |> send_resp(401, "invalid signature") |> halt()

      {:error, %Jason.DecodeError{}} ->
        Logger.warning("Rejected Papra webhook: invalid JSON")
        conn |> send_resp(400, "invalid payload") |> halt()

      {:more, _partial, conn} ->
        Logger.warning("Rejected Papra webhook: body too large")
        conn |> send_resp(413, "payload too large") |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp dispatch(conn, payload, handler) do
    case handler.handle_event(payload) do
      :ok -> conn |> send_resp(200, "ok") |> halt()
      :error -> conn |> send_resp(422, "could not process event") |> halt()
    end
  end

  defp verify_signature(_conn, _raw_body, secret) when secret in [nil, ""] do
    {:error, :invalid_signature}
  end

  defp verify_signature(conn, raw_body, secret) do
    with [msg_id] <- get_req_header(conn, "webhook-id"),
         [timestamp] <- get_req_header(conn, "webhook-timestamp"),
         [sig_header] <- get_req_header(conn, "webhook-signature") do
      signed = "#{msg_id}.#{timestamp}.#{raw_body}"
      expected = "v1," <> (:crypto.mac(:hmac, :sha256, secret, signed) |> Base.encode64())

      if Plug.Crypto.secure_compare(expected, sig_header),
        do: :ok,
        else: {:error, :invalid_signature}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp resolve({m, f, a}), do: apply(m, f, a)
  defp resolve(secret), do: secret
end

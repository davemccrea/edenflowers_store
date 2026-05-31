defmodule EdenflowersWeb.Plugs.PapraWebhook do
  @moduledoc """
  Verifies and dispatches Papra webhook deliveries.

  Mounted in `EdenflowersWeb.Endpoint` *before* `Plug.Parsers` so the raw
  request body is intact for HMAC-SHA256 signature verification — mirroring
  the placement of `Stripe.WebhookPlug`. Only requests whose path matches the
  `:at` option are handled; everything else passes through untouched.

  ## Signature scheme

  This verifies an HMAC-SHA256 hex digest of the raw body, sent in the
  `x-signature` header — the scheme described in Papra's webhook docs. If your
  Papra instance uses the Standard Webhooks scheme (v0.8+), the signed content
  is `"<id>.<timestamp>.<body>"` and the header/encoding differ; adjust
  `verify_signature/3` to match. The secret being unset (`nil`) fails closed —
  every delivery is rejected.
  """
  import Plug.Conn
  require Logger

  @signature_header "x-signature"

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
    expected = :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower)

    case get_req_header(conn, @signature_header) do
      [signature] ->
        if Plug.Crypto.secure_compare(expected, signature),
          do: :ok,
          else: {:error, :invalid_signature}

      _ ->
        {:error, :invalid_signature}
    end
  end

  defp resolve({m, f, a}), do: apply(m, f, a)
  defp resolve(secret), do: secret
end

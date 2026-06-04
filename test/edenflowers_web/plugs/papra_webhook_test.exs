defmodule EdenflowersWeb.Plugs.PapraWebhookTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Conn

  alias EdenflowersWeb.Plugs.PapraWebhook

  @secret "test-webhook-secret"
  @path "/webhook/papra"

  defmodule StubHandler do
    def handle_event(%{"type" => "document:created"}), do: :ok
    def handle_event(_), do: :error
  end

  defp opts do
    PapraWebhook.init(at: @path, handler: StubHandler, secret: @secret)
  end

  defp signed_conn(body, secret \\ @secret, msg_id \\ "msg_123", timestamp \\ "1234567890") do
    signed = "#{msg_id}.#{timestamp}.#{body}"
    sig = "v1," <> (:crypto.mac(:hmac, :sha256, secret, signed) |> Base.encode64())

    Plug.Test.conn(:post, @path, body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("webhook-id", msg_id)
    |> put_req_header("webhook-timestamp", timestamp)
    |> put_req_header("webhook-signature", sig)
  end

  describe "signature verification" do
    test "accepts a correctly signed request" do
      body = ~s({"type":"document:created","data":{"documentId":"d1","organizationId":"o1"}})
      conn = signed_conn(body) |> PapraWebhook.call(opts())
      assert conn.status == 200
    end

    test "rejects a request with a wrong secret" do
      body = ~s({"type":"document:created","data":{"documentId":"d1","organizationId":"o1"}})
      capture_log(fn ->
        conn = signed_conn(body, "wrong-secret") |> PapraWebhook.call(opts())
        assert conn.status == 401
      end)
    end

    test "rejects a request missing webhook-id" do
      body = ~s({"type":"document:created","data":{}})

      capture_log(fn ->
        conn =
          Plug.Test.conn(:post, @path, body)
          |> put_req_header("webhook-timestamp", "1234567890")
          |> put_req_header("webhook-signature", "v1,fakesig")
          |> PapraWebhook.call(opts())

        assert conn.status == 401
      end)
    end

    test "rejects a request missing webhook-signature" do
      capture_log(fn ->
        conn =
          Plug.Test.conn(:post, @path, ~s({}))
          |> put_req_header("webhook-id", "msg_123")
          |> put_req_header("webhook-timestamp", "1234567890")
          |> PapraWebhook.call(opts())

        assert conn.status == 401
      end)
    end

    test "rejects when secret is nil" do
      body = ~s({"type":"document:created","data":{}})
      nil_opts = PapraWebhook.init(at: @path, handler: StubHandler, secret: nil)

      capture_log(fn ->
        conn = signed_conn(body) |> PapraWebhook.call(nil_opts)
        assert conn.status == 401
      end)
    end
  end

  describe "routing" do
    test "passes through requests to other paths" do
      body = ~s({"type":"document:created","data":{}})

      conn =
        Plug.Test.conn(:post, "/webhooks/stripe", body)
        |> PapraWebhook.call(opts())

      refute conn.halted
    end
  end

  describe "payload handling" do
    test "returns 400 for invalid JSON" do
      invalid = "not json"

      capture_log(fn ->
        conn = signed_conn(invalid) |> PapraWebhook.call(opts())
        assert conn.status == 400
      end)
    end

    test "returns 422 when the handler returns :error" do
      body = ~s({"type":"unknown:event","data":{}})
      conn = signed_conn(body) |> PapraWebhook.call(opts())
      assert conn.status == 422
    end
  end
end

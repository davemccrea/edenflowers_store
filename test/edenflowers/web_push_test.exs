defmodule Edenflowers.WebPushTest do
  # Not async: the VAPID keys are application env.
  use Edenflowers.DataCase, async: false

  import Generator

  alias Edenflowers.Accounts
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.PushNewOrder
  alias Edenflowers.WebPush

  # The user agent keys from RFC 8291, appendix A, so the test can decrypt.
  @ua_public "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
  @ua_private "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94"
  @auth_secret "BTBZMqHH6r4Tts7J_aSIgg"

  setup do
    keys = WebPush.generate_keys()
    Application.put_env(:web_push_ex, :vapid, Map.to_list(keys) ++ [subject: "mailto:test@example.com"])
    on_exit(fn -> Application.delete_env(:web_push_ex, :vapid) end)
    %{keys: keys}
  end

  test "delivers a message the browser can decrypt, with a valid VAPID token", %{keys: keys} do
    Req.Test.stub(WebPush, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:pushed, conn, body})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    assert :ok = WebPush.deliver(push_subscription(), "hello")

    assert_received {:pushed, conn, body}
    assert decrypt(body) == "hello"

    ["vapid t=" <> rest] = Plug.Conn.get_req_header(conn, "authorization")
    [token, "k=" <> public_key] = String.split(rest, ", ")
    assert public_key == keys.public_key

    <<4, x::binary-size(32), y::binary-size(32)>> = decode(public_key)
    jwk = JOSE.JWK.from_map(%{"kty" => "EC", "crv" => "P-256", "x" => encode(x), "y" => encode(y)})
    assert {true, %JOSE.JWT{fields: claims}, _jws} = JOSE.JWT.verify_strict(jwk, ["ES256"], token)
    assert claims["aud"] == "https://push.example.com"
    assert claims["sub"] == "mailto:test@example.com"
  end

  test "reports a subscription the push service has forgotten" do
    Req.Test.stub(WebPush, &Plug.Conn.send_resp(&1, 410, ""))
    assert {:error, :gone} = WebPush.deliver(push_subscription(), "hello")
  end

  describe "push subscriptions" do
    test "an admin subscribes, and re-subscribing the same endpoint replaces it" do
      admin = generate(admin_user())

      Accounts.subscribe_to_push!("https://push.example.com/a", @ua_public, @auth_secret, "fi-FI", actor: admin)
      Accounts.subscribe_to_push!("https://push.example.com/a", @ua_public, @auth_secret, "en-GB", actor: admin)

      assert [%{locale: "en-GB", user_id: user_id}] = Accounts.list_push_subscriptions!(actor: admin)
      assert user_id == admin.id
    end

    test "customers can't subscribe" do
      {:ok, customer} = Accounts.upsert_user("ada@example.com", "Ada", authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.subscribe_to_push("https://push.example.com/a", @ua_public, @auth_secret, "fi-FI",
                 actor: customer
               )
    end

    test "an admin only sees their own devices" do
      admin = generate(admin_user())
      other_admin = generate(admin_user())
      Accounts.subscribe_to_push!("https://push.example.com/a", @ua_public, @auth_secret, "fi-FI", actor: other_admin)

      assert Accounts.list_push_subscriptions!(actor: admin) == []
    end

    test "rejects an endpoint that isn't https" do
      admin = generate(admin_user())

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.subscribe_to_push("http://push.example.com/a", @ua_public, @auth_secret, "fi-FI", actor: admin)
    end
  end

  describe "new order notifications" do
    test "placing an order at checkout queues the push" do
      order = generate(order(state: :payment, payment_intent_id: "pi_test"))

      Orders.finalize_checkout!(order.id, order.payment_intent_id, %{amount_paid: "0.00"}, authorize?: false)

      assert_enqueued worker: PushNewOrder, args: %{"order_id" => order.id}
    end

    test "nothing is queued without VAPID keys" do
      Application.delete_env(:web_push_ex, :vapid)
      order = generate(order(state: :payment, payment_intent_id: "pi_test"))

      Orders.finalize_checkout!(order.id, order.payment_intent_id, %{amount_paid: "0.00"}, authorize?: false)

      refute_enqueued worker: PushNewOrder
    end

    test "tells each device about a same-day order and forgets expired ones" do
      admin = generate(admin_user())
      today = Edenflowers.ShopTime.today()
      order = placed_order(fulfillment_date: today, order_reference: "1042")

      Accounts.subscribe_to_push!("https://push.example.com/live", @ua_public, @auth_secret, "en-GB", actor: admin)
      Accounts.subscribe_to_push!("https://push.example.com/gone", @ua_public, @auth_secret, "en-GB", actor: admin)

      Req.Test.stub(WebPush, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        if conn.request_path == "/gone" do
          Plug.Conn.send_resp(conn, 410, "")
        else
          send(self(), {:pushed, Jason.decode!(decrypt(body))})
          Plug.Conn.send_resp(conn, 201, "")
        end
      end)

      assert :ok = perform_job(PushNewOrder, %{"order_id" => order.id})

      assert_received {:pushed, payload}
      assert payload["title"] == "Same-day order 1042"
      assert payload["body"] =~ "Pickup"
      assert payload["body"] =~ "88.50"
      assert payload["tag"] == "order-#{order.id}"
      assert payload["url"] == "/admin/orders/#{order.id}"

      assert [%{endpoint: "https://push.example.com/live"}] = Accounts.list_push_subscriptions!(actor: admin)
    end

    test "skips devices whose user is no longer an admin" do
      {:ok, former_admin} = Accounts.upsert_user("ada@example.com", "Ada", authorize?: false)
      order = placed_order(order_reference: "1043")

      Accounts.subscribe_to_push!("https://push.example.com/former", @ua_public, @auth_secret, "en-GB",
        actor: former_admin,
        authorize?: false
      )

      Req.Test.stub(WebPush, fn conn ->
        send(self(), :pushed)
        Plug.Conn.send_resp(conn, 201, "")
      end)

      assert :ok = perform_job(PushNewOrder, %{"order_id" => order.id})
      refute_received :pushed
    end
  end

  defp push_subscription, do: %{endpoint: "https://push.example.com/send/abc", p256dh: @ua_public, auth: @auth_secret}

  # What the browser does with a message for the RFC's user agent keys.
  defp decrypt(<<salt::binary-size(16), _rs::32, 65, as_public::binary-size(65), sealed::binary>>) do
    ua_public = decode(@ua_public)
    ecdh_secret = :crypto.compute_key(:ecdh, as_public, decode(@ua_private), :prime256v1)
    ikm = hkdf(decode(@auth_secret), ecdh_secret, "WebPush: info\0" <> ua_public <> as_public, 32)
    cek = hkdf(salt, ikm, "Content-Encoding: aes128gcm\0", 16)
    nonce = hkdf(salt, ikm, "Content-Encoding: nonce\0", 12)

    ciphertext_size = byte_size(sealed) - 16
    <<ciphertext::binary-size(ciphertext_size), tag::binary-size(16)>> = sealed
    padded = :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, ciphertext, <<>>, tag, false)
    String.trim_trailing(padded, <<2>>)
  end

  defp hkdf(salt, ikm, info, length) do
    prk = :crypto.mac(:hmac, :sha256, salt, ikm)
    :crypto.mac(:hmac, :sha256, prk, info <> <<1>>) |> binary_part(0, length)
  end

  defp decode(value), do: Base.url_decode64!(value, padding: false)
  defp encode(value), do: Base.url_encode64(value, padding: false)
end

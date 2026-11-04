defmodule EdenflowersWeb.Admin.BankConnectionTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Edenflowers.Bank.Connection
  alias Edenflowers.External.EnableBankingAPI
  alias EdenflowersWeb.Admin.BankController

  setup :log_in_admin

  @login_url "https://tilisy.enablebanking.com/ais/start?sessionid=test"

  test "Connect bank sends Jennie to the S-Pankki login with a signed request", %{conn: conn} do
    Req.Test.stub(EnableBankingAPI, fn conn ->
      assert_signed(conn)

      case conn.request_path do
        "/aspsps" ->
          Req.Test.json(conn, %{"aspsps" => [%{"name" => "S-Pankki", "maximum_consent_validity" => 15_552_000}]})

        "/auth" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = JSON.decode!(body)
          assert request["aspsp"] == %{"name" => "S-Pankki", "country" => "FI"}
          assert request["redirect_url"] =~ "/admin/bank/callback"
          Req.Test.json(conn, %{"url" => @login_url})
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/expenses")
    assert has_element?(view, "#bank-status", "Bank not connected")

    assert {:error, {:redirect, %{to: @login_url}}} = view |> element("#bank-status button") |> render_click()
  end

  test "the bank's redirect stores the session and shows until when it's connected", %{conn: conn, admin: user} do
    Req.Test.stub(EnableBankingAPI, fn %{request_path: "/sessions"} = conn ->
      Req.Test.json(conn, %{
        "session_id" => "session-1",
        "accounts" => [%{"uid" => "account-1"}],
        "access" => %{"valid_until" => "2027-05-03T10:00:00Z"}
      })
    end)

    conn = get(conn, ~p"/admin/bank/callback?#{[state: BankController.sign_state(user), code: "code-1"]}")
    assert redirected_to(conn) == ~p"/admin/expenses"

    assert [%{session_id: "session-1", account_ids: ["account-1"]}] = Ash.read!(Connection, authorize?: false)

    {:ok, view, _html} = live(conn, ~p"/admin/expenses")
    assert has_element?(view, "#bank-status", "Bank connected")
    assert has_element?(view, "#bank-status", "Reconnect")
  end

  test "warns from two weeks before the consent ends", %{conn: conn} do
    seed_connection(DateTime.add(DateTime.utc_now(), 10, :day))

    {:ok, view, _html} = live(conn, ~p"/admin/expenses")

    assert has_element?(view, "#bank-status", "Bank connection ending")
  end

  test "an ended consent shows the bank as disconnected", %{conn: conn} do
    seed_connection(DateTime.add(DateTime.utc_now(), -1, :day))

    {:ok, view, _html} = live(conn, ~p"/admin/expenses")

    assert has_element?(view, "#bank-status", "Bank disconnected")
  end

  test "a callback with someone else's state stores nothing", %{conn: conn} do
    Req.Test.stub(EnableBankingAPI, fn _conn -> flunk("Enable Banking was called") end)
    state = BankController.sign_state(%{id: Ash.UUID.generate()})

    conn = get(conn, ~p"/admin/bank/callback?#{[state: state, code: "code-1"]}")

    assert redirected_to(conn) == ~p"/admin/expenses"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "wasn't connected"
    assert Ash.read!(Connection, authorize?: false) == []
  end

  test "a code the bank rejects stores nothing", %{conn: conn, admin: user} do
    Req.Test.stub(EnableBankingAPI, fn conn ->
      conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"error" => "invalid code"})
    end)

    conn = get(conn, ~p"/admin/bank/callback?#{[state: BankController.sign_state(user), code: "used"]}")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "wasn't connected"
    assert Ash.read!(Connection, authorize?: false) == []
  end

  defp seed_connection(valid_until) do
    Ash.Seed.seed!(Connection, %{session_id: "session-1", account_ids: ["account-1"], valid_until: valid_until})
  end

  defp assert_signed(conn) do
    ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")
    public_key = :edenflowers |> Application.fetch_env!(:enable_banking) |> Keyword.fetch!(:private_key)
    jwk = public_key |> JOSE.JWK.from_pem() |> JOSE.JWK.to_public()

    assert {true, %JOSE.JWT{fields: %{"aud" => "api.enablebanking.com", "iss" => "enablebanking.com"}}, jws} =
             JOSE.JWT.verify_strict(jwk, ["RS256"], token)

    assert jws.fields["kid"] == "test-application-id"
  end
end

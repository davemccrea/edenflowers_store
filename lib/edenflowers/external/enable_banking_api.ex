defmodule Edenflowers.External.EnableBankingAPI do
  @moduledoc """
  Thin client for Enable Banking, which reads the shop's S-Pankki account
  under PSD2 (https://enablebanking.com/docs/api/reference/).

  Every request carries a short-lived JWT signed with the Production
  application's private key. Only production has the key, so dev and
  worktrees never reach the bank.
  """

  @base_url "https://api.enablebanking.com"
  @aspsp %{name: "S-Pankki", country: "FI"}

  @doc "Whether the application ID and private key are configured. Only production has them."
  def configured?, do: config() != nil

  @doc """
  Starts a consent for the shop's S-Pankki account, as long as the bank allows.
  Returns the URL Jennie logs in at; the bank sends her back to `redirect_url`
  with `state` and a one-time `code`.
  """
  def start_authorization(state, redirect_url) do
    with {:ok, seconds} <- maximum_consent_seconds(),
         valid_until = DateTime.utc_now() |> DateTime.add(seconds) |> DateTime.truncate(:second),
         {:ok, %{"url" => url}} <-
           request(:post, "/auth",
             json: %{
               access: %{valid_until: DateTime.to_iso8601(valid_until)},
               aspsp: @aspsp,
               state: state,
               redirect_url: redirect_url,
               psu_type: "business"
             }
           ) do
      {:ok, url}
    end
  end

  @doc "Swaps the `code` from the bank's redirect for a session on the accounts Jennie approved."
  def create_session(code) do
    with {:ok, %{"session_id" => session_id, "accounts" => accounts, "access" => %{"valid_until" => valid_until}}} <-
           request(:post, "/sessions", json: %{code: code}),
         {:ok, valid_until, _offset} <- DateTime.from_iso8601(valid_until) do
      {:ok, %{session_id: session_id, account_ids: Enum.map(accounts, & &1["uid"]), valid_until: valid_until}}
    else
      {:error, _reason} = error -> error
      response -> {:error, {:enable_banking_unexpected_session, response}}
    end
  end

  defp maximum_consent_seconds do
    with {:ok, %{"aspsps" => aspsps}} <- request(:get, "/aspsps", params: [country: @aspsp.country]) do
      case Enum.find(aspsps, &(&1["name"] == @aspsp.name)) do
        %{"maximum_consent_validity" => seconds} when is_integer(seconds) -> {:ok, seconds}
        _ -> {:error, :enable_banking_aspsp_not_found}
      end
    end
  end

  defp request(method, path, options) do
    request = [method: method, url: @base_url <> path, auth: {:bearer, jwt()}] ++ options

    case Req.request(request ++ req_options()) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:enable_banking_http_error, status, body}}
      {:error, reason} -> {:error, {:enable_banking_request_failed, reason}}
    end
  end

  defp jwt do
    %{application_id: application_id, private_key: private_key} = Map.new(config())
    now = System.system_time(:second)
    claims = %{"iss" => "enablebanking.com", "aud" => "api.enablebanking.com", "iat" => now, "exp" => now + 3600}

    private_key
    |> JOSE.JWK.from_pem()
    |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => application_id, "typ" => "JWT"}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp config, do: Application.get_env(:edenflowers, :enable_banking)
  defp req_options, do: Application.get_env(:edenflowers, :enable_banking_req_options, [])
end

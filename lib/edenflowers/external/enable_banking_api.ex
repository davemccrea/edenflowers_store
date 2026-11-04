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
               # The shop's account is linked in Enable Banking as Jennie's personal one.
               psu_type: "personal"
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

  @doc """
  The account's booked transactions from `date_from` on, every page of them,
  each as `%{id, direction, amount, currency, booked_on, reference_number, counterparty, message}`.
  `direction` is `:out` for a payment from the account, `:in` for one to it.

  Options:
    * `:date_to` - the last booking date to read.
    * `:psu_headers` - Jennie's browser, as `[{"psu-ip-address", ip}, ...]`, when
      she asked for the read. The bank then counts her as present, so the read
      doesn't use one of the four a day it allows without her. Any PSU header
      makes the bank expect all it requires (`required_psu_headers` in `/aspsps`),
      so pass every one there is.
  """
  def booked_transactions(account_id, date_from, options \\ []) do
    params =
      [date_from: Date.to_iso8601(date_from), transaction_status: "BOOK"] ++
        case options[:date_to] do
          nil -> []
          date_to -> [date_to: Date.to_iso8601(date_to)]
        end

    fetch_transactions(account_id, params, Keyword.get(options, :psu_headers, []), [])
  end

  defp fetch_transactions(account_id, params, headers, acc) do
    with {:ok, %{"transactions" => transactions} = page} <-
           request(:get, "/accounts/#{account_id}/transactions", params: params, headers: headers) do
      acc = acc ++ Enum.map(transactions, &transaction/1)

      case page["continuation_key"] do
        key when is_binary(key) and key != "" ->
          fetch_transactions(account_id, Keyword.put(params, :continuation_key, key), headers, acc)

        _last_page ->
          {:ok, acc}
      end
    end
  end

  defp transaction(transaction) do
    direction = if(transaction["credit_debit_indicator"] == "CRDT", do: :in, else: :out)
    counterparty = if direction == :in, do: transaction["debtor"], else: transaction["creditor"]

    %{
      id: transaction["entry_reference"] || transaction["transaction_id"],
      direction: direction,
      amount: Decimal.new(transaction["transaction_amount"]["amount"]),
      currency: String.downcase(transaction["transaction_amount"]["currency"]),
      booked_on: Date.from_iso8601!(transaction["booking_date"]),
      reference_number: transaction["reference_number"],
      counterparty: counterparty && counterparty["name"],
      message: transaction["remittance_information"] |> List.wrap() |> Enum.join(" ")
    }
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

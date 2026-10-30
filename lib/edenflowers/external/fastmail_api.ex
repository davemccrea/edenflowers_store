defmodule Edenflowers.External.FastmailAPI do
  @moduledoc """
  Thin JMAP client for the shop's Fastmail mailbox.

  Finds folders, lists the emails in one with their attachments, downloads an
  attachment and moves an email between folders. Used by
  `Edenflowers.Expenses.Actions.ImportInvoiceEmails`. Authenticates with an API
  token that needs mail write access, since importing moves emails.
  """

  @session_url "https://api.fastmail.com/jmap/session"
  @mail_capability "urn:ietf:params:jmap:mail"
  @using ["urn:ietf:params:jmap:core", @mail_capability]

  @doc "Whether an API token is configured. Only production has one."
  def configured?, do: token() != nil

  def connect do
    case get_json(@session_url) do
      {:ok,
       %{"apiUrl" => api_url, "downloadUrl" => download_url, "primaryAccounts" => %{@mail_capability => account_id}}} ->
        {:ok, %{api_url: api_url, download_url: download_url, account_id: account_id}}

      {:ok, _session} ->
        {:error, :fastmail_mail_account_missing}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~S'Finds a folder by its names from the top level down, e.g. `["Fakturor", "Importerade"]`.'
  def mailbox_id(conn, path) do
    with {:ok, [%{"list" => mailboxes}]} <-
           call(conn, [["Mailbox/get", %{accountId: conn.account_id, properties: ["name", "parentId"]}, "m"]]) do
      Enum.reduce_while(path, {:ok, nil}, fn name, {:ok, parent_id} ->
        find_child(mailboxes, parent_id, name, path)
      end)
    end
  end

  defp find_child(mailboxes, parent_id, name, path) do
    case Enum.find(mailboxes, &(&1["name"] == name and &1["parentId"] == parent_id)) do
      nil -> {:halt, {:error, {:fastmail_mailbox_not_found, Enum.join(path, "/")}}}
      mailbox -> {:cont, {:ok, mailbox["id"]}}
    end
  end

  # ponytail: 50 emails per call; the rest come on the next poll.
  def list_emails(conn, mailbox_id) do
    calls = [
      ["Email/query", %{accountId: conn.account_id, filter: %{inMailbox: mailbox_id}, limit: 50}, "q"],
      [
        "Email/get",
        %{
          :accountId => conn.account_id,
          "#ids" => %{resultOf: "q", name: "Email/query", path: "/ids"},
          :properties => ["attachments"]
        },
        "g"
      ]
    ]

    with {:ok, [_query, %{"list" => emails}]} <- call(conn, calls) do
      {:ok, Enum.map(emails, &%{id: &1["id"], attachments: Enum.map(&1["attachments"], fn a -> attachment(a) end)})}
    end
  end

  def download(conn, attachment) do
    url =
      conn.download_url
      |> String.replace("{accountId}", URI.encode_www_form(conn.account_id))
      |> String.replace("{blobId}", URI.encode_www_form(attachment.blob_id))
      |> String.replace("{name}", URI.encode_www_form(attachment.name))
      |> String.replace("{type}", URI.encode_www_form(attachment.type))

    case Req.get([url: url, auth: {:bearer, token()}, decode_body: false] ++ req_options()) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:fastmail_http_error, status}}
      {:error, reason} -> {:error, {:fastmail_request_failed, reason}}
    end
  end

  def move_email(conn, email_id, from_mailbox_id, to_mailbox_id) do
    update = %{email_id => %{"mailboxIds/#{from_mailbox_id}" => nil, "mailboxIds/#{to_mailbox_id}" => true}}

    case call(conn, [["Email/set", %{accountId: conn.account_id, update: update}, "s"]]) do
      {:ok, [%{"updated" => %{^email_id => _}}]} -> :ok
      {:ok, [%{"notUpdated" => %{^email_id => error}}]} -> {:error, {:fastmail_move_failed, error}}
      {:ok, response} -> {:error, {:fastmail_move_failed, response}}
      {:error, error} -> {:error, error}
    end
  end

  defp attachment(attachment) do
    %{
      blob_id: attachment["blobId"],
      name: attachment["name"] || "attachment",
      type: attachment["type"] || "application/octet-stream"
    }
  end

  defp call(conn, method_calls) do
    request = [url: conn.api_url, json: %{using: @using, methodCalls: method_calls}, auth: {:bearer, token()}]

    case Req.post(request ++ req_options()) do
      {:ok, %Req.Response{status: 200, body: %{"methodResponses" => responses}}} ->
        method_results(responses)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:fastmail_http_error, status}}

      {:error, reason} ->
        {:error, {:fastmail_request_failed, reason}}
    end
  end

  # Returns each method's response arguments, in call order.
  defp method_results(responses) do
    case Enum.find(responses, fn [name, _arguments, _id] -> name == "error" end) do
      nil -> {:ok, Enum.map(responses, fn [_name, arguments, _id] -> arguments end)}
      [_name, error, _id] -> {:error, {:fastmail_method_error, error}}
    end
  end

  defp get_json(url) do
    case Req.get([url: url, auth: {:bearer, token()}] ++ req_options()) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:fastmail_http_error, status}}
      {:error, reason} -> {:error, {:fastmail_request_failed, reason}}
    end
  end

  defp token, do: Application.get_env(:edenflowers, :fastmail_api_token)
  defp req_options, do: Application.get_env(:edenflowers, :fastmail_req_options, [])
end

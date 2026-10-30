defmodule Edenflowers.Expenses.ImportInvoiceEmailsTest do
  # Not async: one test unsets the Fastmail token in the application env.
  use Edenflowers.DataCase, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.ExpenseImport
  alias Edenflowers.External.FastmailAPI
  alias Edenflowers.External.PapraAPI

  setup :verify_on_exit!

  @hetzner %{
    "id" => "email_hetzner",
    "attachments" => [
      %{"blobId" => "blob_invoice", "name" => "Hetzner_2026-10.pdf", "type" => "application/pdf"},
      %{"blobId" => "blob_terms", "name" => "terms.PDF", "type" => "application/octet-stream"},
      %{"blobId" => "blob_logo", "name" => "logo.png", "type" => "image/png"}
    ]
  }
  @link_only %{"id" => "email_link", "attachments" => []}

  @default_mailboxes [
    %{"id" => "mb_fakturor", "name" => "Fakturor", "parentId" => nil},
    %{"id" => "mb_importerade", "name" => "Importerade", "parentId" => "mb_fakturor"},
    # A same-named folder elsewhere must not be mistaken for the imported folder.
    %{"id" => "mb_other", "name" => "Importerade", "parentId" => nil}
  ]

  test "uploads each PDF, records it for extraction and moves the email; leaves emails without a PDF" do
    stub_fastmail([@hetzner, @link_only])

    expect(PapraAPI.Mock, :upload_document, fn "Hetzner_2026-10.pdf", "bytes of blob_invoice" ->
      {:ok, %{document_id: "doc_invoice", organization_id: "org_test"}}
    end)

    expect(PapraAPI.Mock, :upload_document, fn "terms.PDF", "bytes of blob_terms" ->
      {:ok, %{document_id: "doc_terms", organization_id: "org_test"}}
    end)

    assert :ok = import_invoice_emails()

    assert ["doc_invoice", "doc_terms"] = imported_document_ids()
    assert_received {:moved, "email_hetzner", %{"mailboxIds/mb_fakturor" => nil, "mailboxIds/mb_importerade" => true}}
    refute_received {:moved, "email_link", _update}
  end

  test "a PDF already in Papra counts as imported but alerts" do
    stub_fastmail([%{@hetzner | "attachments" => Enum.take(@hetzner["attachments"], 1)}])
    expect(PapraAPI.Mock, :upload_document, fn _name, _body -> {:error, :already_exists} end)

    log = capture_log(fn -> assert :ok = import_invoice_emails() end)

    assert log =~ "[error]"
    assert log =~ "Hetzner_2026-10.pdf is already in Papra"
    assert imported_document_ids() == []
    assert_received {:moved, "email_hetzner", _update}
  end

  test "a failed upload leaves the email in the folder and fails the run" do
    stub_fastmail([@hetzner])
    expect(PapraAPI.Mock, :upload_document, fn _name, _body -> {:error, {:papra_http_error, 500}} end)

    assert {:error, _error} = import_invoice_emails()

    refute_received {:moved, _email_id, _update}
  end

  test "a missing folder fails the run" do
    stub_fastmail([@hetzner], mailboxes: [%{"id" => "mb_fakturor", "name" => "Fakturor", "parentId" => nil}])

    assert {:error, error} = import_invoice_emails()
    assert Exception.message(error) =~ "Fakturor/Importerade"
  end

  test "does nothing without a Fastmail token" do
    token = Application.fetch_env!(:edenflowers, :fastmail_api_token)
    Application.delete_env(:edenflowers, :fastmail_api_token)
    on_exit(fn -> Application.put_env(:edenflowers, :fastmail_api_token, token) end)

    Req.Test.stub(FastmailAPI, fn _conn -> flunk("Fastmail was called") end)

    assert :ok = import_invoice_emails()
  end

  defp import_invoice_emails, do: Expenses.import_invoice_emails(actor: Edenflowers.Actors.system_actor())

  defp imported_document_ids do
    ExpenseImport |> Ash.read!(authorize?: false) |> Enum.map(& &1.document_id) |> Enum.sort()
  end

  # A fake JMAP server holding `emails` in `Fakturor`. Moves are sent to the test process.
  defp stub_fastmail(emails, opts \\ []) do
    test_pid = self()
    mailboxes = Keyword.get(opts, :mailboxes, @default_mailboxes)

    Req.Test.stub(FastmailAPI, fn conn ->
      case {conn.method, conn.path_info} do
        {"GET", ["jmap", "session"]} ->
          Req.Test.json(conn, %{
            "apiUrl" => "https://api.fastmail.test/jmap/api",
            "downloadUrl" => "https://download.fastmail.test/{accountId}/{blobId}/{name}?type={type}",
            "primaryAccounts" => %{"urn:ietf:params:jmap:mail" => "account_1"}
          })

        {"POST", ["jmap", "api"]} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          %{"methodCalls" => calls} = Jason.decode!(body)
          responses = Enum.map(calls, &respond(&1, emails, mailboxes, test_pid))
          Req.Test.json(conn, %{"methodResponses" => responses})

        {"GET", ["account_1", blob_id, _name]} ->
          Plug.Conn.send_resp(conn, 200, "bytes of #{blob_id}")
      end
    end)
  end

  defp respond(["Mailbox/get", _arguments, id], _emails, mailboxes, _test_pid) do
    ["Mailbox/get", %{"list" => mailboxes}, id]
  end

  defp respond(["Email/query", %{"filter" => %{"inMailbox" => "mb_fakturor"}}, id], emails, _mailboxes, _test_pid) do
    ["Email/query", %{"ids" => Enum.map(emails, & &1["id"])}, id]
  end

  defp respond(["Email/get", %{"#ids" => %{"resultOf" => "q"}}, id], emails, _mailboxes, _test_pid) do
    ["Email/get", %{"list" => emails}, id]
  end

  defp respond(["Email/set", %{"update" => update}, id], _emails, _mailboxes, test_pid) do
    Enum.each(update, fn {email_id, patch} -> send(test_pid, {:moved, email_id, patch}) end)
    ["Email/set", %{"updated" => Map.new(update, fn {email_id, _patch} -> {email_id, nil} end)}, id]
  end
end

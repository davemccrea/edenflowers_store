defmodule Edenflowers.Minimossen.ImportWinposReportsTest do
  # Not async: one test unsets the Fastmail token in the application env.
  use Edenflowers.DataCase, async: false

  alias Edenflowers.External.FastmailAPI
  alias Edenflowers.Minimossen
  alias Edenflowers.Minimossen.WeeklySales

  @blobs %{
    "blob_flowers" => "flowers-2026-11-02.XLS",
    "blob_shop" => "shop-2026-11-02.XLS"
  }

  @winpos %{
    "id" => "email_winpos",
    "attachments" => [
      %{
        "blobId" => "blob_flowers",
        "name" => "Tuoteryhmät 20261108121504944.XLS",
        "type" => "application/vnd.ms-excel"
      },
      %{"blobId" => "blob_shop", "name" => "Tuoteryhmät 20261108121502132.XLS", "type" => "application/octet-stream"}
    ]
  }
  @no_report %{"id" => "email_text", "attachments" => []}

  @mailboxes [
    %{"id" => "mb_winpos", "name" => "Winpos", "parentId" => nil},
    %{"id" => "mb_importerade", "name" => "Importerade", "parentId" => "mb_winpos"}
  ]

  test "records each group's week from every report and moves the email; leaves emails without one" do
    stub_fastmail([@winpos, @no_report])

    assert :ok = import_reports()

    assert gross_by_group() == %{"3" => "154.40", "6" => "221.40", "7" => "160.50", "66" => "25.00"}
    assert_received {:moved, "email_winpos", %{"mailboxIds/mb_winpos" => nil, "mailboxIds/mb_importerade" => true}}
    refute_received {:moved, "email_text", _update}
  end

  test "importing the same report again overwrites instead of duplicating" do
    stub_fastmail([@winpos])

    assert :ok = import_reports()
    assert :ok = import_reports()

    assert length(Ash.read!(WeeklySales, actor: Edenflowers.Actors.system_actor())) == 4
  end

  test "an unreadable report records nothing from its email, leaves it in the folder and fails the run" do
    broken = %{"blobId" => "blob_broken", "name" => "broken.XLS", "type" => "application/vnd.ms-excel"}
    stub_fastmail([%{@winpos | "attachments" => @winpos["attachments"] ++ [broken]}])

    assert {:error, error} = import_reports()
    assert Exception.message(error) =~ "broken.XLS"

    assert gross_by_group() == %{}
    refute_received {:moved, _email_id, _update}
  end

  test "does nothing without a Fastmail token" do
    token = Application.fetch_env!(:edenflowers, :fastmail_api_token)
    Application.delete_env(:edenflowers, :fastmail_api_token)
    on_exit(fn -> Application.put_env(:edenflowers, :fastmail_api_token, token) end)

    Req.Test.stub(FastmailAPI, fn _conn -> flunk("Fastmail was called") end)

    assert :ok = import_reports()
  end

  defp import_reports, do: Minimossen.import_winpos_reports(actor: Edenflowers.Actors.system_actor())

  defp gross_by_group do
    WeeklySales
    |> Ash.read!(actor: Edenflowers.Actors.system_actor())
    |> Map.new(&{&1.group_code, Decimal.to_string(&1.gross, :normal)})
  end

  # A fake JMAP server holding `emails` in `Winpos`. Moves are sent to the test process.
  defp stub_fastmail(emails) do
    test_pid = self()

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
          Req.Test.json(conn, %{"methodResponses" => Enum.map(calls, &respond(&1, emails, test_pid))})

        {"GET", ["account_1", blob_id, _name]} ->
          Plug.Conn.send_resp(conn, 200, blob(blob_id))
      end
    end)
  end

  defp blob(blob_id) do
    case @blobs do
      %{^blob_id => fixture} -> File.read!(Path.expand("../../support/fixtures/winpos/#{fixture}", __DIR__))
      _other -> "not a spreadsheet"
    end
  end

  defp respond(["Mailbox/get", _arguments, id], _emails, _test_pid), do: ["Mailbox/get", %{"list" => @mailboxes}, id]

  defp respond(["Email/query", %{"filter" => %{"inMailbox" => "mb_winpos"}}, id], emails, _test_pid) do
    ["Email/query", %{"ids" => Enum.map(emails, & &1["id"])}, id]
  end

  defp respond(["Email/get", %{"#ids" => %{"resultOf" => "q"}}, id], emails, _test_pid) do
    ["Email/get", %{"list" => emails}, id]
  end

  defp respond(["Email/set", %{"update" => update}, id], _emails, test_pid) do
    Enum.each(update, fn {email_id, patch} -> send(test_pid, {:moved, email_id, patch}) end)
    ["Email/set", %{"updated" => Map.new(update, fn {email_id, _patch} -> {email_id, nil} end)}, id]
  end
end

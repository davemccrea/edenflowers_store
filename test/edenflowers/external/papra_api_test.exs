defmodule Edenflowers.External.PapraAPITest do
  use ExUnit.Case, async: true

  alias Edenflowers.External.PapraAPI

  test "renames a document" do
    Req.Test.stub(PapraAPI, fn %{method: "PATCH", request_path: "/api/organizations/org_test/documents/doc_1"} = conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:renamed, Jason.decode!(body)})
      Req.Test.json(conn, %{})
    end)

    assert :ok = PapraAPI.rename_document("doc_1", "2026-10-23 Kukkatukku Oy.pdf")
    assert_received {:renamed, %{"name" => "2026-10-23 Kukkatukku Oy.pdf"}}
  end

  test "fetches a document with the type its bytes show, not the type Papra labels it" do
    png = <<0x89, "PNG", "\r\n", 0x1A, "\n", "rest">>

    Req.Test.stub(PapraAPI, fn %{method: "GET", request_path: "/api/organizations/org_test/documents/doc_1/file"} = conn ->
      conn |> Plug.Conn.put_resp_content_type("application/pdf") |> Plug.Conn.send_resp(200, png)
    end)

    assert {:ok, %{body: ^png, content_type: "image/png"}} = PapraAPI.fetch_document("org_test", "doc_1")
  end
end

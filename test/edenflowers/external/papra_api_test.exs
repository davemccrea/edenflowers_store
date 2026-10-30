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
end

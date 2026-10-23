defmodule Edenflowers.External.PapraAPITest do
  use ExUnit.Case, async: true

  alias Edenflowers.External.PapraAPI

  @tags %{"tags" => [%{"id" => "tag_other", "name" => "invoice"}, %{"id" => "tag_receipt", "name" => "receipt"}]}

  test "removes the tag by looking up its ID" do
    Req.Test.stub(PapraAPI, fn
      %{method: "GET", request_path: "/api/organizations/org_test/tags"} = conn ->
        Req.Test.json(conn, @tags)

      %{method: "DELETE", request_path: "/api/organizations/org_test/documents/doc_1/tags/tag_receipt"} = conn ->
        send(self(), :deleted)
        Plug.Conn.send_resp(conn, 204, "")
    end)

    assert :ok = PapraAPI.remove_document_tag("doc_1", "receipt")
    assert_received :deleted
  end

  test "does nothing when the organization has no such tag" do
    Req.Test.stub(PapraAPI, fn %{method: "GET"} = conn -> Req.Test.json(conn, %{"tags" => []}) end)

    assert :ok = PapraAPI.remove_document_tag("doc_1", "receipt")
  end

  test "treats a document that no longer has the tag as done" do
    Req.Test.stub(PapraAPI, fn
      %{method: "GET"} = conn -> Req.Test.json(conn, @tags)
      %{method: "DELETE"} = conn -> Plug.Conn.send_resp(conn, 404, "")
    end)

    assert :ok = PapraAPI.remove_document_tag("doc_1", "receipt")
  end

  test "returns an error when Papra fails" do
    Req.Test.stub(PapraAPI, fn
      %{method: "GET"} = conn -> Req.Test.json(conn, @tags)
      %{method: "DELETE"} = conn -> Plug.Conn.send_resp(conn, 500, "")
    end)

    assert {:error, {:papra_http_error, 500}} = PapraAPI.remove_document_tag("doc_1", "receipt")
  end

  test "adds a tag by looking up its ID" do
    Req.Test.stub(PapraAPI, fn
      %{method: "GET"} = conn ->
        Req.Test.json(conn, %{"tags" => [%{"id" => "tag_processed", "name" => "processed"}]})

      %{method: "POST", request_path: "/api/organizations/org_test/documents/doc_1/tags"} = conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(self(), {:added, Jason.decode!(body)})
        Plug.Conn.send_resp(conn, 204, "")
    end)

    assert :ok = PapraAPI.add_document_tag("doc_1", "processed")
    assert_received {:added, %{"tagId" => "tag_processed"}}
  end

  test "can't add a tag that doesn't exist in Papra" do
    Req.Test.stub(PapraAPI, fn %{method: "GET"} = conn -> Req.Test.json(conn, %{"tags" => []}) end)

    assert {:error, {:papra_tag_not_found, "processed"}} = PapraAPI.add_document_tag("doc_1", "processed")
  end

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

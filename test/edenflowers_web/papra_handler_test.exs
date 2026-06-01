defmodule EdenflowersWeb.PapraHandlerTest do
  use Edenflowers.DataCase

  import Mox

  setup :verify_on_exit!

  setup do
    Edenflowers.Repo.delete_all(Oban.Job)
    :ok
  end

  describe "document:created" do
    test "enqueues a ProcessExpenseDocument job" do
      assert :ok =
               EdenflowersWeb.PapraHandler.handle_event(%{
                 "type" => "document:created",
                 "data" => %{
                   "documentId" => "doc_abc123",
                   "organizationId" => "org_xyz456",
                   "name" => "receipt.pdf"
                 }
               })

      assert_enqueued(
        worker: Edenflowers.Workers.ProcessExpenseDocument,
        args: %{"document_id" => "doc_abc123", "organization_id" => "org_xyz456"}
      )
    end

    test "is idempotent: a duplicate event collapses to one job" do
      event = %{
        "type" => "document:created",
        "data" => %{
          "documentId" => "doc_dup",
          "organizationId" => "org_xyz456"
        }
      }

      assert :ok = EdenflowersWeb.PapraHandler.handle_event(event)
      assert :ok = EdenflowersWeb.PapraHandler.handle_event(event)

      assert [_single_job] =
               all_enqueued(worker: Edenflowers.Workers.ProcessExpenseDocument)
    end

    test "returns :error when documentId is missing" do
      assert :error =
               EdenflowersWeb.PapraHandler.handle_event(%{
                 "type" => "document:created",
                 "data" => %{"organizationId" => "org_xyz456"}
               })

      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end

    test "returns :error when organizationId is missing" do
      assert :error =
               EdenflowersWeb.PapraHandler.handle_event(%{
                 "type" => "document:created",
                 "data" => %{"documentId" => "doc_abc123"}
               })

      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end
  end

  describe "unhandled events" do
    test "returns :ok for unrecognised event types" do
      assert :ok =
               EdenflowersWeb.PapraHandler.handle_event(%{
                 "type" => "document:tag:added",
                 "data" => %{}
               })

      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end
  end
end

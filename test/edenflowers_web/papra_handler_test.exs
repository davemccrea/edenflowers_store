defmodule EdenflowersWeb.PapraHandlerTest do
  use Edenflowers.DataCase

  import ExUnit.CaptureLog
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

    test "returns :error and logs when documentId is missing" do
      log =
        capture_log(fn ->
          assert :error =
                   EdenflowersWeb.PapraHandler.handle_event(%{
                     "type" => "document:created",
                     "data" => %{"organizationId" => "org_xyz456"}
                   })
        end)

      assert log =~ "documentId"
      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end

    test "returns :error and logs when organizationId is missing" do
      log =
        capture_log(fn ->
          assert :error =
                   EdenflowersWeb.PapraHandler.handle_event(%{
                     "type" => "document:created",
                     "data" => %{"documentId" => "doc_abc123"}
                   })
        end)

      assert log =~ "organizationId"
      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end
  end

  describe "unhandled events" do
    test "returns :ok and logs for unrecognised event types" do
      log =
        capture_log(fn ->
          assert :ok =
                   EdenflowersWeb.PapraHandler.handle_event(%{
                     "type" => "document:tag:added",
                     "data" => %{}
                   })
        end)

      assert log =~ "document:tag:added"
      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end
  end
end

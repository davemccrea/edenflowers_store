defmodule EdenflowersWeb.Webhooks.PapraHandlerTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Mox

  alias EdenflowersWeb.Webhooks.PapraHandler

  setup :verify_on_exit!

  setup do
    Edenflowers.Repo.delete_all(Oban.Job)
    :ok
  end

  describe "document:created" do
    test "records an import and enqueues its processing trigger" do
      assert :ok =
               PapraHandler.handle_event(%{
                 "type" => "document:created",
                 "data" => %{
                   "documentId" => "doc_abc123",
                   "organizationId" => "org_xyz456"
                 }
               })

      assert_enqueued(worker: Edenflowers.Expenses.Workers.Process)
    end

    test "is idempotent: a duplicate event collapses to one job" do
      event = %{
        "type" => "document:created",
        "data" => %{
          "documentId" => "doc_dup",
          "organizationId" => "org_xyz456"
        }
      }

      assert :ok = PapraHandler.handle_event(event)
      assert :ok = PapraHandler.handle_event(event)

      assert [_single_job] =
               all_enqueued(worker: Edenflowers.Expenses.Workers.Process)
    end

    test "returns :error when documentId is missing" do
      capture_log(fn ->
        assert :error =
                 PapraHandler.handle_event(%{
                   "type" => "document:created",
                   "data" => %{"organizationId" => "org_xyz456"}
                 })
      end)

      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end

    test "returns :error when organizationId is missing" do
      capture_log(fn ->
        assert :error =
                 PapraHandler.handle_event(%{
                   "type" => "document:created",
                   "data" => %{"documentId" => "doc_abc123"}
                 })
      end)

      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end
  end

  describe "document:deleted" do
    defp deleted(document_id) do
      PapraHandler.handle_event(%{
        "type" => "document:deleted",
        "data" => %{"documentId" => document_id, "organizationId" => "org_xyz456"}
      })
    end

    defp record(document_id) do
      Edenflowers.Expenses.record_expense_import!(
        %{document_id: document_id, organization_id: "org_xyz456"},
        actor: Edenflowers.Actors.system_actor()
      )
    end

    test "deletes the document's expense and import, leaving other documents alone" do
      record("doc_gone")
      record("doc_kept")

      for document_id <- ["doc_gone", "doc_kept"] do
        Edenflowers.Expenses.ingest_expense!(
          %{document_id: document_id, sure: true},
          actor: Edenflowers.Actors.system_actor()
        )
      end

      assert :ok = deleted("doc_gone")

      assert [%{document_id: "doc_kept"}] = Ash.read!(Edenflowers.Expenses.Expense, authorize?: false)
      assert [%{document_id: "doc_kept"}] = Ash.read!(Edenflowers.Expenses.ExpenseImport, authorize?: false)
    end

    test "deletes an import that never became an expense, so a re-upload imports it again" do
      record("doc_pending")

      assert :ok = deleted("doc_pending")
      assert [] = Ash.read!(Edenflowers.Expenses.ExpenseImport, authorize?: false)
    end

    test "is a no-op for a document that was never imported" do
      assert :ok = deleted("doc_unknown")
    end

    test "returns :error when documentId is missing" do
      capture_log(fn ->
        assert :error = PapraHandler.handle_event(%{"type" => "document:deleted", "data" => %{}})
      end)
    end
  end

  describe "unhandled events" do
    test "returns :ok for unrecognised event types" do
      assert :ok =
               PapraHandler.handle_event(%{
                 "type" => "document:updated",
                 "data" => %{}
               })

      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end
  end
end

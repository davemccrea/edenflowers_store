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

  describe "unhandled events" do
    test "returns :ok for unrecognised event types" do
      assert :ok =
               PapraHandler.handle_event(%{
                 "type" => "document:deleted",
                 "data" => %{}
               })

      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
    end
  end
end

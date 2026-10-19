defmodule Edenflowers.Orders.EmailFailureTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendOrderDetailsEmail
  alias Edenflowers.Orders.Workers.SendReceiptEmail

  @moduletag capture_log: true

  test "a receipt that fails its last attempt is recorded, logged and published" do
    order = placed_order(paid: true)
    EdenflowersWeb.Endpoint.subscribe("order:email:#{order.id}")

    fail_last_attempt(SendReceiptEmail, order)

    assert Orders.get_order_by_id!(order.id, authorize?: false).receipt_email_failed_at
    assert :record_receipt_email_failure in versions(order)
    assert_receive %Phoenix.Socket.Broadcast{event: "record_receipt_email_failure"}
  end

  test "order details that fail their last attempt are recorded, and a resend clears them" do
    order = placed_order(origin: :custom)
    EdenflowersWeb.Endpoint.subscribe("order:email:#{order.id}")

    fail_last_attempt(SendOrderDetailsEmail, order)

    assert Orders.get_order_by_id!(order.id, authorize?: false).order_details_email_failed_at
    assert :record_order_details_email_failure in versions(order)
    assert_receive %Phoenix.Socket.Broadcast{event: "record_order_details_email_failure"}

    {:ok, _order} = Orders.send_order_details_email(order, actor: generate(admin_user()))

    refute Orders.get_order_by_id!(order.id, authorize?: false).order_details_email_failed_at
  end

  @tag :typst
  test "resending the receipt clears a recorded failure" do
    order = placed_order(paid: true, receipt_email_failed_at: DateTime.utc_now())

    {:ok, _order} = Orders.email_receipt(order, actor: generate(admin_user()))

    refute Orders.get_order_by_id!(order.id, authorize?: false).receipt_email_failed_at
  end

  test "no scheduler requeues a customer email" do
    refute Code.ensure_loaded?(Edenflowers.Orders.Schedulers.SendReceiptEmail)
    refute Code.ensure_loaded?(Edenflowers.Orders.Schedulers.SendOrderDetailsEmail)
  end

  # What the worker does once a job's last attempt has failed.
  defp fail_last_attempt(worker, order) do
    primary_key = %{"id" => order.id}
    job = %Oban.Job{attempt: 3, max_attempts: 3, args: %{"primary_key" => primary_key}}
    worker.handle_error(job, RuntimeError.exception("mail server down"), primary_key, [])
  end

  defp versions(order) do
    order
    |> Ash.load!(:paper_trail_versions, authorize?: false)
    |> Map.fetch!(:paper_trail_versions)
    |> Enum.map(& &1.version_action_name)
  end
end

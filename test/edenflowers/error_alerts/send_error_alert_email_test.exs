defmodule Edenflowers.ErrorAlerts.SendErrorAlertEmailTest do
  use Edenflowers.DataCase, async: false

  alias Edenflowers.Repo
  import Swoosh.TestAssertions

  alias Edenflowers.ErrorAlerts.SendErrorAlertEmail
  alias Edenflowers.ErrorTrackerLogHandler

  setup do
    Application.put_env(:error_tracker, :enabled, true)
    on_exit(fn -> Application.put_env(:error_tracker, :enabled, false) end)
  end

  defp log_error(message) do
    ErrorTrackerLogHandler.report(%{
      msg: {:string, message},
      meta: %{mfa: {Edenflowers.Orders.Payment, :setup_payment, 2}, file: ~c"payment.ex", line: 20}
    })
  end

  test "emails once for a new error, not for repeat occurrences" do
    log_error("Failed to create payment intent for order abc")
    log_error("Failed to create payment intent for order def")

    [error] = Repo.all(ErrorTracker.Error)
    assert [_job] = all_enqueued(worker: SendErrorAlertEmail)

    assert {:ok, _} = perform_job(SendErrorAlertEmail, %{"error_id" => error.id})

    assert_email_sent(fn email ->
      assert email.to == [{"", "alerts@example.com"}]
      assert email.subject =~ "Failed to create payment intent"
      assert email.text_body =~ "/admin/errors/#{error.id}"
    end)
  end

  test "emails again when a resolved error comes back" do
    log_error("Failed to create payment intent for order abc")
    [error] = Repo.all(ErrorTracker.Error)
    ErrorTracker.resolve(error)
    Repo.delete_all(Oban.Job)

    log_error("Failed to create payment intent for order abc")

    assert_enqueued(worker: SendErrorAlertEmail, args: %{"error_id" => error.id})
  end

  test "skips muted errors" do
    log_error("Failed to create payment intent for order abc")
    [error] = Repo.all(ErrorTracker.Error)
    ErrorTracker.mute(error)

    assert :ok = perform_job(SendErrorAlertEmail, %{"error_id" => error.id})

    assert_no_email_sent()
  end
end

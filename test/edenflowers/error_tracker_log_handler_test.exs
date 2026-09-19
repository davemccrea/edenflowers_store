defmodule Edenflowers.ErrorTrackerLogHandlerTest do
  use Edenflowers.DataCase, async: false

  alias Edenflowers.ErrorTrackerLogHandler

  setup do
    Application.put_env(:error_tracker, :enabled, true)
    on_exit(fn -> Application.put_env(:error_tracker, :enabled, false) end)
  end

  test "stores a logged error grouped by the logging call site" do
    event = %{
      level: :error,
      msg: {:string, ["Amount mismatch for order ", "abc"]},
      meta: %{mfa: {EdenflowersWeb.Webhooks.StripeHandler, :handle_error, 2}, file: ~c"stripe_handler.ex", line: 89}
    }

    ErrorTrackerLogHandler.report(event)
    ErrorTrackerLogHandler.report(event)

    assert [error] = Repo.all(ErrorTracker.Error)
    assert error.reason == "Amount mismatch for order abc"
    assert error.source_function == "EdenflowersWeb.Webhooks.StripeHandler.handle_error/2"
    assert Repo.aggregate(ErrorTracker.Occurrence, :count) == 2
  end

  test "only reports errors logged by our own code" do
    assert ErrorTrackerLogHandler.reportable?(%{mfa: {Edenflowers.Orders.Payment, :setup_payment, 2}})
    assert ErrorTrackerLogHandler.reportable?(%{mfa: {EdenflowersWeb.CheckoutLive, :handle_event, 3}})

    refute ErrorTrackerLogHandler.reportable?(%{mfa: {Ecto.Adapters.SQL, :query, 4}})
    refute ErrorTrackerLogHandler.reportable?(%{mfa: {Edenflowers.Orders.Payment, :x, 0}, crash_reason: {:boom, []}})
    refute ErrorTrackerLogHandler.reportable?(%{})
  end
end

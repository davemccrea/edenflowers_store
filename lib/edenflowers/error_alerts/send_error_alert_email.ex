defmodule Edenflowers.ErrorAlerts.SendErrorAlertEmail do
  @moduledoc """
  Emails the error alert address when ErrorTracker sees a new error, or one
  that was resolved comes back. Repeat occurrences of an unresolved error don't
  alert, so a burst of the same failure sends a single email.
  """

  # Several occurrences can arrive before the first job runs.
  use Oban.Worker, queue: :default, unique: [keys: [:error_id], period: 300]

  require Logger

  alias Edenflowers.{Email, Mailer, Repo}

  @events [[:error_tracker, :error, :new], [:error_tracker, :error, :unresolved]]

  def attach do
    :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, nil)
  end

  def handle_event(_event, _measurements, %{error: error}, _config) do
    %{"error_id" => error.id} |> new() |> Oban.insert()
  rescue
    # Telemetry detaches a handler that raises, which would stop all alerts.
    exception -> Logger.warning("Failed to enqueue error alert: #{Exception.message(exception)}")
  end

  def perform(%Oban.Job{args: %{"error_id" => error_id}}) do
    case Repo.get(ErrorTracker.Error, error_id) do
      %{muted: false, status: :unresolved} = error -> error |> Email.error_alert() |> Mailer.deliver()
      _muted_resolved_or_deleted -> :ok
    end
  end
end

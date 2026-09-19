defmodule Edenflowers.ErrorTrackerLogHandler do
  @moduledoc """
  Reports `Logger.error` calls made from our own code to ErrorTracker.

  ErrorTracker only captures exceptions, but most payment failures are handled
  and logged rather than raised, so they would otherwise never reach the
  dashboard. Errors are grouped by the module, function and line that logged
  them. Crashes are skipped because ErrorTracker's Phoenix and Oban
  integrations already report those.
  """

  defmodule LoggedError do
    defexception [:message]
  end

  def log(%{meta: meta} = event, _config) do
    if reportable?(meta) do
      # Reporting inside the caller could join its DB transaction and be rolled
      # back with it.
      Task.start(fn -> report(event) end)
    end

    :ok
  end

  @doc false
  def report(%{msg: msg, meta: %{mfa: {module, function, arity}} = meta}) do
    stacktrace = [{module, function, arity, [file: meta[:file], line: meta[:line]]}]
    context = %{"request_id" => meta[:request_id]}

    ErrorTracker.report(%LoggedError{message: message(msg)}, stacktrace, context)
  end

  @doc false
  def reportable?(%{mfa: {module, _function, _arity}} = meta) do
    not Map.has_key?(meta, :crash_reason) and app_module?(module)
  end

  def reportable?(_meta), do: false

  defp app_module?(module) do
    module |> Atom.to_string() |> String.starts_with?(["Elixir.Edenflowers.", "Elixir.EdenflowersWeb."])
  end

  defp message({:string, chardata}), do: IO.chardata_to_string(chardata)
  defp message({:report, report}), do: inspect(report)
  defp message({format, args}), do: format |> :io_lib.format(args) |> IO.chardata_to_string()
end

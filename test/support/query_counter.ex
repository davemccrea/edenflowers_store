defmodule EdenflowersWeb.QueryCounter do
  @moduledoc """
  Records SELECT queries from a LiveView process so tests can distinguish a
  targeted refresh from a full reload. Call `track/1` before the work under
  test, then inspect the recorded table names with `sources/1`.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc """
  Returns an ETS table that records SELECT queries from `pid` and processes
  whose `$callers` list includes `pid`, such as its async tasks. The telemetry
  handler is detached when the test exits.
  """
  def track(pid) do
    table = :ets.new(:tracked_reads, [:public, :duplicate_bag])
    ref = make_ref()

    :ok =
      :telemetry.attach(
        ref,
        [:edenflowers, :repo, :query],
        fn _event, _measurements, metadata, table ->
          if reads_as?(pid) and String.starts_with?(metadata.query, "SELECT") do
            :ets.insert(table, {metadata.source})
          end
        end,
        table
      )

    on_exit(fn -> :telemetry.detach(ref) end)
    table
  end

  @doc "Returns the recorded source table names, with one entry per SELECT query."
  def sources(table), do: Enum.map(:ets.tab2list(table), &elem(&1, 0))

  @doc "Returns the number of SELECT queries recorded so far."
  def count(table), do: :ets.info(table, :size)

  @doc "Clears recorded queries without stopping tracking, so the next operation can be measured separately."
  def clear(table), do: :ets.delete_all_objects(table)

  defp reads_as?(pid), do: self() == pid or pid in Process.get(:"$callers", [])
end

defmodule EdenflowersWeb.QueryCounter do
  @moduledoc """
  Records the SELECTs a LiveView process runs, so a test can tell a cheap
  refresh from a full one. Add rows to the table only while the work under
  test runs, then read `sources/1`.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc """
  Starts counting the reads `pid` runs, including those it spawns. The table
  stays empty until something is read.
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

  @doc "The tables read so far, one entry per SELECT."
  def sources(table), do: Enum.map(:ets.tab2list(table), &elem(&1, 0))

  @doc "How many SELECTs ran."
  def count(table), do: :ets.info(table, :size)

  @doc "Forgets the reads so far, keeping the tracking."
  def clear(table), do: :ets.delete_all_objects(table)

  defp reads_as?(pid), do: self() == pid or pid in Process.get(:"$callers", [])
end

defmodule Mix.Tasks.Gettext.Stats do
  @moduledoc """
  Run `mix gettext.stats` after `mix gettext.extract --merge` to see translation
  progress. Empty English translations use the source text and are not missing.
  Fuzzy entries need review even when they contain a translation.
  """

  use Mix.Task

  @shortdoc "Shows translation progress by audience and priority"

  @critical ~w(storefront emails receipts shared errors routes)

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Locale  Priority  Domain       Ready  Missing  Review  Total")

    for locale <- ~w(en sv fi),
        domain <- @critical ++ ~w(admin cinder),
        path = "priv/gettext/#{locale}/LC_MESSAGES/#{domain}.po",
        File.exists?(path) do
      report(locale, domain, path)
    end

    Mix.shell().info("\nEnglish source text counts as ready. Obsolete entries are excluded.")
  end

  defp report(locale, domain, path) do
    messages = path |> Expo.PO.parse_file!() |> Map.fetch!(:messages) |> Enum.reject(& &1.obsolete)
    counts = Enum.frequencies_by(messages, &state(&1, locale))
    priority = if domain in @critical, do: "critical", else: "can wait"

    row = [
      String.pad_trailing(locale, 8),
      String.pad_trailing(priority, 10),
      String.pad_trailing(domain, 13),
      String.pad_leading(to_string(Map.get(counts, :ready, 0)), 5),
      String.pad_leading(to_string(Map.get(counts, :missing, 0)), 9),
      String.pad_leading(to_string(Map.get(counts, :review, 0)), 8),
      String.pad_leading(to_string(length(messages)), 7)
    ]

    Mix.shell().info(IO.iodata_to_binary(row))
  end

  defp state(message, locale) do
    cond do
      Expo.Message.has_flag?(message, "fuzzy") -> :review
      locale == "en" -> :ready
      translated?(message.msgstr) -> :ready
      true -> :missing
    end
  end

  defp translated?(plurals) when is_map(plurals), do: Enum.all?(plurals, fn {_, text} -> translated?(text) end)
  defp translated?(text), do: text |> IO.iodata_to_binary() |> String.trim() != ""
end

defmodule EdenflowersWeb.DesignRulesTest do
  @moduledoc """
  Mechanical checks for DESIGN.md's rules, so the doc doesn't have to keep
  an inventory of call sites.
  """
  use ExUnit.Case, async: true

  # The Square Edge Rule: the radius tokens make everything square, so the only
  # radius utility markup may use is rounded-full (and rounded-none, which some
  # daisyUI components still need).
  test "markup uses no radius utility other than rounded-full" do
    offenders = matches(~r/\brounded-(?!full\b|none\b)[\w\[\]\/.-]+/)
    assert offenders == [], "Radius utilities outside rounded-full:\n" <> Enum.join(offenders, "\n")
  end

  # The Hairline Rule: lines are drawn in base-content/12 (or ink, or /20). base-300 is
  # only the resting edge of a choice that turns primary when selected.
  @base_300_choices [
    "lib/edenflowers_web/components/core_components.ex",
    "lib/edenflowers_web/components/card_drawer.ex"
  ]

  test "base-300 borders appear only on selectable choices" do
    offenders =
      ~r/\b(border|divide)-base-300\b/
      |> matches()
      |> Enum.reject(&String.starts_with?(&1, Enum.map(@base_300_choices, fn path -> path <> ":" end)))

    assert offenders == [], "Lines drawn in base-300 (use base-content/12):\n" <> Enum.join(offenders, "\n")
  end

  defp matches(regex) do
    for path <- Path.wildcard("lib/**/*.{ex,heex}"),
        {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
        Regex.match?(regex, line) do
      "#{path}:#{number}: #{String.trim(line)}"
    end
  end
end

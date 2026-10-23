defmodule EdenflowersWeb.PrettierFormatter do
  @moduledoc """
  Formats the JavaScript in colocated hooks with prettier when `mix format`
  runs, registered under `tag_formatters` in `.formatter.exs`. Adapted from the
  example in `Phoenix.LiveView.HTMLFormatter.TagFormatter`.
  """

  @behaviour Phoenix.LiveView.HTMLFormatter.TagFormatter

  require Logger

  # The version `just format` and the pre-commit hook run on .js files.
  @prettier "prettier@3.3.3"

  @impl true
  def render_tag({"script", attrs, content}, _opts) do
    suffix = if Map.has_key?(attrs, ":type"), do: Map.get(attrs, "manifest", "index.js"), else: "tmp.js"
    tmp_file = Path.join(System.tmp_dir!(), "prettier_#{System.unique_integer([:positive])}_#{suffix}")

    try do
      File.write!(tmp_file, content)

      case System.cmd("npx", ["--yes", @prettier, tmp_file], stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, String.trim(output)}

        {error, _} ->
          Logger.error("Failed to format with prettier: #{error}")
          :skip
      end
    after
      File.rm(tmp_file)
    end
  end
end

defmodule EdenflowersWeb.PrettierFormatter do
  @moduledoc """
  Formats colocated JavaScript and CSS with prettier when `mix format` runs,
  registered under `tag_formatters` in `.formatter.exs`. Adapted from the
  example in `Phoenix.LiveView.HTMLFormatter.TagFormatter`.
  """

  @behaviour Phoenix.LiveView.HTMLFormatter.TagFormatter

  require Logger

  # The version `just format` runs on asset files.
  @prettier "prettier@3.3.3"

  @impl true
  def render_tag({tag, attrs, content}, _opts) when tag in ["script", "style"] do
    # Prettier preserves indentation inside CSS comments. Remove the template's
    # outer indentation so repeated formatting doesn't keep adding it there.
    content = if tag == "style", do: dedent(content), else: content

    suffix =
      cond do
        tag == "style" -> "tmp.css"
        Map.has_key?(attrs, ":type") -> Map.get(attrs, "manifest", "index.js")
        true -> "tmp.js"
      end

    tmp_file = Path.join(System.tmp_dir!(), "prettier_#{System.unique_integer([:positive])}_#{suffix}")

    try do
      File.write!(tmp_file, content)

      case System.cmd("npx", ["--yes", @prettier, tmp_file],
             stderr_to_stdout: true,
             env: Edenflowers.ChildEnv.without_secrets()
           ) do
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

  defp dedent(content) do
    case Regex.run(~r/\A[\t ]*\r?\n([\t ]+)\S/, content) do
      [_, indent] -> String.replace(content, "\n" <> indent, "\n")
      _ -> content
    end
  end
end

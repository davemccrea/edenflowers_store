defmodule Mix.Tasks.Gettext.Update do
  @moduledoc "Extracts messages and merges only the languages supported by each catalogue."
  use Mix.Task

  @shortdoc "Updates translations respecting the admin/customer language policy"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("gettext.extract")
    merge("priv/gettext", args)
  end

  @doc false
  def merge(root, args \\ []) do
    for template <- Path.wildcard(Path.join(root, "*.pot")),
        domain = Path.basename(template, ".pot"),
        locale <- Edenflowers.TranslationCatalogues.locales(domain) do
      catalogue = Path.join([root, locale, "LC_MESSAGES", "#{domain}.po"])
      Mix.Tasks.Gettext.Merge.run([catalogue, template] ++ args)
    end
  end
end

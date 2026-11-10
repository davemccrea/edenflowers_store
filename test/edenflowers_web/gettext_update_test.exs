defmodule EdenflowersWeb.GettextUpdateTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  test "updating catalogues preserves Finnish storefront copy without creating Finnish admin", %{tmp_dir: root} do
    template = "msgid \"Hello\"\nmsgstr \"\"\n"

    for domain <- ~w(storefront admin) do
      File.write!(Path.join(root, "#{domain}.pot"), template)

      for locale <- Edenflowers.TranslationCatalogues.locales(domain) do
        path = Path.join([root, locale, "LC_MESSAGES", "#{domain}.po"])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, String.replace(template, "msgstr \"\"", "msgstr \"Hei\""))
      end
    end

    ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Gettext.Update.merge(root, ["--no-fuzzy"]) end)

    refute File.exists?(Path.join([root, "fi", "LC_MESSAGES", "admin.po"]))
    catalogue = Expo.PO.parse_file!(Path.join([root, "fi", "LC_MESSAGES", "storefront.po"]))
    assert [%{msgstr: ["Hei"]}] = catalogue.messages
  end
end

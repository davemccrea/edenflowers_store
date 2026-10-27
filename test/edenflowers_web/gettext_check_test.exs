defmodule EdenflowersWeb.GettextCheckTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gettext.Check

  @moduletag :tmp_dir
  @singular ~s(msgid "Hello %{name}"\nmsgstr "Hei %{name}"\n)
  @plural """
  msgid "%{count} item"
  msgid_plural "%{count} items"
  msgstr[0] "%{count} tuote"
  msgstr[1] "%{count} tuotetta"
  """

  setup %{tmp_dir: root} do
    catalogue(root, "storefront", @singular)
    File.write!(Path.join(root, "check-exceptions.json"), "[]")
    %{root: root}
  end

  test "valid catalogues pass and empty English translations use source", %{root: root} do
    translate(root, "en", "storefront", "msgid \"Hello %{name}\"\nmsgstr \"\"\n")
    assert Check.check(root) == []
    assert ExUnit.CaptureIO.capture_io(fn -> Check.run(["--root", root]) end) =~ "checks passed"
  end

  test "missing and unexpected placeholders fail, including non-Gettext markers", %{root: root} do
    for translation <- ["Hei", "Hei %{name} %{other}", "Hei %{name} {selector}", "Hei %{name} __N__"] do
      translate(root, "fi", "storefront", "msgid \"Hello %{name}\"\nmsgstr \"#{translation}\"\n")
      assert [%{"kind" => "placeholders", "locale" => "fi"}] = Check.check(root)
    end
  end

  test "every plural form is checked against its own source", %{root: root} do
    catalogue(root, "storefront", @plural)
    assert Check.check(root) == []

    translate(root, "fi", "storefront", String.replace(@plural, "%{count} tuotetta", "tuotetta"))
    assert [%{"kind" => "placeholders", "form" => 1}] = Check.check(root)

    translate(root, "fi", "storefront", String.replace(@plural, "msgstr[1] \"%{count} tuotetta\"\n", ""))
    assert [%{"kind" => "plural_forms"}] = Check.check(root)
  end

  test "missing and fuzzy customer-facing translations fail", %{root: root} do
    translate(root, "fi", "storefront", String.replace(@singular, "Hei %{name}", ""))
    assert [%{"kind" => "missing"}] = Check.check(root)

    translate(root, "fi", "storefront", "#, fuzzy\n" <> @singular)
    assert [%{"kind" => "fuzzy"}] = Check.check(root)
  end

  test "admin coverage can wait but its placeholders must still be valid", %{root: root} do
    catalogue(root, "admin", @singular)
    translate(root, "fi", "admin", String.replace(@singular, "Hei %{name}", ""))
    assert Check.check(root) == []

    translate(root, "fi", "admin", String.replace(@singular, "Hei %{name}", "Hei"))
    assert [%{"kind" => "placeholders", "domain" => "admin"}] = Check.check(root)
  end

  test "all domains require matching contexts, singular and plural sources", %{root: root} do
    catalogue(root, "cinder", @plural)
    translate(root, "fi", "cinder", String.replace(@plural, "%{count} items", "%{count} things"))
    assert [%{"kind" => "alignment", "domain" => "cinder"}] = Check.check(root)

    translate(root, "fi", "cinder", "msgctxt \"other meaning\"\n" <> @plural)
    assert [%{"kind" => "alignment"}] = Check.check(root)
  end

  test "obsolete entries do not affect checks", %{root: root} do
    translate(root, "fi", "storefront", @singular <> "\n#~ msgid \"Old %{name}\"\n#~ msgstr \"Vanha\"\n")
    assert Check.check(root) == []
  end

  test "exceptions match exact text and become errors when obsolete", %{root: root} do
    translate(root, "fi", "storefront", String.replace(@singular, "Hei %{name}", "Hei"))
    [issue] = Check.check(root)
    File.write!(Path.join(root, "check-exceptions.json"), Jason.encode!([Map.put(issue, "reason", "Test exception")]))
    ExUnit.CaptureIO.capture_io(fn -> Check.run(["--root", root]) end)

    translate(root, "fi", "storefront", String.replace(@singular, "Hei %{name}", "Terve"))

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise Mix.Error, ~r/1 issues, 1 stale exceptions/, fn -> Check.run(["--root", root]) end
    end)

    translate(root, "fi", "storefront", @singular)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise Mix.Error, ~r/0 issues, 1 stale exceptions/, fn -> Check.run(["--root", root]) end
    end)
  end

  test "exceptions require a reason", %{root: root} do
    File.write!(Path.join(root, "check-exceptions.json"), Jason.encode!([%{"reason" => " "}]))
    assert_raise Mix.Error, ~r/non-empty reason/, fn -> Check.run(["--root", root]) end
  end

  test "catalogues without a template are not silently skipped", %{root: root} do
    catalogue(root, "unknown", @singular)
    File.rm!(Path.join(root, "unknown.pot"))
    assert_raise File.Error, fn -> Check.check(root) end
  end

  test "Cinder uses its dependency template when no local template exists", %{root: root} do
    template = Path.join([Mix.Project.deps_path(), "cinder", "i18n/gettext/cinder.pot"])
    text = File.read!(template)
    for locale <- ~w(sv fi), do: translate(root, locale, "cinder", text)
    assert Check.check(root) == []
  end

  test "malformed or absent catalogues fail instead of being skipped", %{root: root} do
    translate(root, "fi", "storefront", "not a PO file")
    assert_raise Expo.PO.SyntaxError, fn -> Check.check(root) end

    File.rm!(Path.join([root, "fi", "LC_MESSAGES", "storefront.po"]))
    assert_raise File.Error, fn -> Check.check(root) end
  end

  defp catalogue(root, domain, text) do
    File.write!(Path.join(root, "#{domain}.pot"), text)
    for locale <- ~w(en sv fi), do: translate(root, locale, domain, text)
  end

  defp translate(root, locale, domain, text) do
    directory = Path.join([root, locale, "LC_MESSAGES"])
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "#{domain}.po"), text)
  end
end

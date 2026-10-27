defmodule Mix.Tasks.Gettext.Check do
  @moduledoc """
  Checks catalogue alignment, plural forms, placeholders and customer-facing
  translation coverage. Reviewed exceptions live in priv/gettext/check-exceptions.json.
  Exceptions match exact text and must be removed when no longer needed.
  """
  use Mix.Task

  @shortdoc "Checks translations for mechanical errors and coverage regressions"
  @critical ~w(storefront emails receipts shared errors routes)
  @locales ~w(en sv fi)

  @impl Mix.Task
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: [root: :string])
    root = Keyword.get(opts, :root, "priv/gettext")
    exceptions = root |> Path.join("check-exceptions.json") |> File.read!() |> Jason.decode!()

    unless Enum.all?(exceptions, &(is_binary(&1["reason"]) and String.trim(&1["reason"]) != "")) do
      Mix.raise("Every translation exception needs a non-empty reason.")
    end

    issues = check(root)
    allowed = Enum.map(exceptions, &Map.delete(&1, "reason"))
    failures = issues -- allowed
    stale = allowed -- issues

    if failures != [] or stale != [] do
      Enum.each(failures, &Mix.shell().error(Jason.encode!(&1)))
      Enum.each(stale, &Mix.shell().error("Remove stale exception: #{Jason.encode!(&1)}"))
      Mix.raise("Translation checks failed (#{length(failures)} issues, #{length(stale)} stale exceptions).")
    end

    Mix.shell().info("Translation checks passed (#{length(allowed)} documented exceptions).")
  end

  @doc false
  def check(root) do
    templates = Path.wildcard(Path.join(root, "*.pot"))

    if templates == [] do
      Mix.raise("No Gettext templates found in #{root}")
    end

    catalogue_domains =
      root
      |> Path.join("*/LC_MESSAGES/*.po")
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".po"))

    domains = Enum.uniq(Enum.map(templates, &Path.basename(&1, ".pot")) ++ catalogue_domains)

    Enum.flat_map(domains, fn domain ->
      template = messages(template_path(root, domain))
      locales = if domain == "cinder", do: ~w(sv fi), else: @locales

      Enum.flat_map(locales, fn locale ->
        catalogue_path = Path.join([root, locale, "LC_MESSAGES", "#{domain}.po"])
        catalogue = messages(catalogue_path)

        alignment_issues(template, catalogue, locale, domain) ++
          Enum.flat_map(catalogue, &message_issues(&1, locale, domain))
      end)
    end)
  end

  defp template_path(root, "cinder") do
    local = Path.join(root, "cinder.pot")

    if File.exists?(local) do
      local
    else
      Path.join([Mix.Project.deps_path(), "cinder", "i18n/gettext/cinder.pot"])
    end
  end

  defp template_path(root, domain), do: Path.join(root, "#{domain}.pot")

  defp messages(path) do
    path |> Expo.PO.parse_file!() |> Map.fetch!(:messages) |> Enum.reject(& &1.obsolete)
  end

  defp alignment_issues(template, catalogue, locale, domain) do
    expected = MapSet.new(template, &signature/1)
    actual = MapSet.new(catalogue, &signature/1)

    if expected == actual do
      []
    else
      [%{"kind" => "alignment", "locale" => locale, "domain" => domain}]
    end
  end

  defp signature(%Expo.Message.Plural{} = message) do
    {Expo.Message.key(message), IO.iodata_to_binary(message.msgid_plural)}
  end

  defp signature(message), do: {Expo.Message.key(message), nil}

  defp message_issues(message, locale, domain) do
    plural_issues(message, locale, domain) ++
      review_issues(message, locale, domain) ++
      Enum.flat_map(forms(message), &form_issues(&1, message, locale, domain))
  end

  defp form_issues({form, source, translation}, message, locale, domain) do
    cond do
      locale == "en" and translation == "" ->
        []

      String.trim(translation) == "" and domain in @critical ->
        [issue(message, locale, domain, "missing", form, translation)]

      String.trim(translation) == "" ->
        []

      markers(source) != markers(translation) ->
        [issue(message, locale, domain, "placeholders", form, translation)]

      true ->
        []
    end
  end

  defp plural_issues(%Expo.Message.Plural{msgstr: translations} = message, locale, domain) do
    if Enum.sort(Map.keys(translations)) == [0, 1] do
      []
    else
      [issue(message, locale, domain, "plural_forms", nil, nil)]
    end
  end

  defp plural_issues(_message, _locale, _domain), do: []

  defp review_issues(message, locale, domain) do
    if locale != "en" and domain in @critical and Expo.Message.has_flag?(message, "fuzzy") do
      [issue(message, locale, domain, "fuzzy", nil, nil)]
    else
      []
    end
  end

  defp forms(%Expo.Message.Plural{} = message) do
    Enum.map(message.msgstr, fn {index, translation} ->
      source = if index == 0, do: message.msgid, else: message.msgid_plural
      {index, IO.iodata_to_binary(source), IO.iodata_to_binary(translation)}
    end)
  end

  defp forms(message), do: [{nil, IO.iodata_to_binary(message.msgid), IO.iodata_to_binary(message.msgstr)}]

  defp markers(text) do
    ~r/%\{[^}]+\}|\{selector\}|__N__/
    |> Regex.scan(text)
    |> List.flatten()
    |> MapSet.new()
  end

  defp issue(message, locale, domain, kind, form, translation) do
    {context, source} = Expo.Message.key(message)

    %{
      "kind" => kind,
      "locale" => locale,
      "domain" => domain,
      "context" => context,
      "source" => source,
      "form" => form,
      "translation" => translation
    }
  end
end

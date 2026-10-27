defmodule Edenflowers.Feedback.Catalogue do
  @moduledoc """
  Finds the Gettext messages behind text a reviewer Option+Clicked, by matching the
  rendered text against the `.po` catalogues in `priv/gettext`. Nothing in the page
  marks which message rendered what, so this is a reverse lookup: the same wording in
  several catalogues gives several matches, and text from the database gives none.
  """

  alias Expo.Message

  @locales ~w(en fi sv)
  # URL segments, never visible text, and short enough to match navigation labels.
  @skipped_domains ~w(routes)
  @max_matches 10

  @type match :: %{
          domain: String.t(),
          msgctxt: String.t() | nil,
          msgid: String.t(),
          translations: %{String.t() => String.t()}
        }

  @doc """
  The messages whose text, as `locale` renders it, equals one of `texts`. A
  `%{placeholder}` matches any text. Each match carries its text in every locale.
  """
  @spec matches([String.t()], String.t()) :: [match]
  def matches(texts, locale) do
    locale = locale |> to_string() |> String.split("-") |> hd() |> String.downcase()
    texts = texts |> Enum.map(&normalize/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    if locale in @locales and texts != [] do
      # ponytail: parses the catalogues on every lookup (reviewers only, a few per minute);
      # cache in :persistent_term if it ever shows up as slow.
      catalogues = Map.new(@locales, &{&1, messages(&1)})

      catalogues[locale]
      |> Enum.sort()
      |> Enum.filter(fn {_key, message} -> Enum.any?(rendered(message), &matches_any?(&1, texts)) end)
      |> Enum.take(@max_matches)
      |> Enum.map(fn {{domain, msgctxt, msgid} = key, _message} ->
        %{
          domain: domain,
          msgctxt: msgctxt,
          msgid: msgid,
          translations:
            Map.new(@locales, fn other ->
              {other, catalogues[other] |> Map.get(key) |> display()}
            end)
        }
      end)
    else
      []
    end
  end

  defp messages(locale) do
    Path.wildcard(Path.join([Application.app_dir(:edenflowers, "priv/gettext"), locale, "LC_MESSAGES", "*.po"]))
    |> Enum.reject(&(Path.basename(&1, ".po") in @skipped_domains))
    |> Enum.flat_map(fn path ->
      domain = Path.basename(path, ".po")

      for message <- Expo.PO.parse_file!(path).messages, not message.obsolete do
        {{domain, message.msgctxt && IO.iodata_to_binary(message.msgctxt), IO.iodata_to_binary(message.msgid)}, message}
      end
    end)
    |> Map.new()
  end

  # What Gettext shows at runtime: the translation, or the English source while it is
  # missing or fuzzy.
  defp rendered(%Message.Singular{} = message) do
    msgstr = IO.iodata_to_binary(message.msgstr)

    if msgstr == "" or Message.has_flag?(message, "fuzzy"),
      do: [IO.iodata_to_binary(message.msgid)],
      else: [msgstr]
  end

  defp rendered(%Message.Plural{} = message) do
    forms = message.msgstr |> Enum.sort() |> Enum.map(fn {_n, form} -> IO.iodata_to_binary(form) end)

    if Enum.any?(forms, &(&1 == "")) or Message.has_flag?(message, "fuzzy"),
      do: [IO.iodata_to_binary(message.msgid), IO.iodata_to_binary(message.msgid_plural)],
      else: forms
  end

  defp display(nil), do: nil
  defp display(message), do: message |> rendered() |> Enum.join(" | ")

  defp matches_any?(candidate, texts) do
    candidate = normalize(candidate)
    parts = Regex.split(~r/%\{\w+\}/, candidate)

    case parts do
      [literal] ->
        literal in texts

      parts ->
        # A message that is mostly placeholder, like "%{count} kpl", would match far too much.
        if parts |> Enum.join() |> String.trim() |> String.length() < 4 do
          false
        else
          pattern = Regex.compile!("^" <> Enum.map_join(parts, ".+?", &Regex.escape/1) <> "$", "u")
          Enum.any?(texts, &Regex.match?(pattern, &1))
        end
    end
  end

  # Catalogue text can hold markup the page renders as elements; the picker sends text.
  defp normalize(text) do
    text
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end

defmodule Edenflowers.Feedback do
  @moduledoc """
  Entry point for review notes: comments reviewers leave on any element of the
  site with Option+Click. There is no admin page for them; `just review-comments`
  prints the open ones from production and agents resolve them as they fix each.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  alias Edenflowers.Actors

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Feedback.Note do
      define :leave_note, action: :leave
      define :list_open_notes, action: :open
      define :list_open_notes_on_page, action: :open_on_page, args: [:path]
      define :find_strings, args: [:texts, :locale]
      define :edit_note, action: :edit, get_by: [:id]
      define :delete_note, action: :delete, get_by: [:id]
      define :resolve_note, action: :resolve, get_by: [:number]
    end
  end

  @doc "The open notes as Markdown, oldest first, for `just review-comments`."
  def open_notes_markdown do
    case list_open_notes!(actor: Actors.system_actor(), load: [:author]) do
      [] -> "No open review notes."
      notes -> Enum.map_join(notes, "\n\n", &note_markdown/1)
    end
  end

  defp note_markdown(note) do
    """
    ## ##{note.number}

    Comment: #{note.body}

    - Page: #{note.path} (#{note.locale}, #{note.viewport}, #{note.app_version})
    - By: #{note.author.email}, #{Calendar.strftime(note.inserted_at, "%Y-%m-%d %H:%M")} UTC
    - Selector: `#{note.selector}`
    #{if note.source, do: "- Source: #{note.source}\n", else: ""}#{strings_markdown(note.strings)}- Text: #{inspect(note.element_text)}

    ```html
    #{note.element_html}
    ```
    """
    |> String.trim_trailing()
  end

  defp strings_markdown(strings) do
    Enum.map_join(strings, fn string ->
      context = if string["msgctxt"], do: " (msgctxt #{inspect(string["msgctxt"])})", else: ""
      "- String: #{string["domain"]}.po#{context} msgid #{inspect(string["msgid"])}\n"
    end)
  end
end

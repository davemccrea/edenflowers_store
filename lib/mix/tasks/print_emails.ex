defmodule Mix.Tasks.PrintEmails do
  @moduledoc """
  Prints every wording variant of every customer email from
  `Edenflowers.Email.Previews`, as Markdown, so an agent can review the copy
  and its translations.

  ## Usage

      mix print_emails          # Swedish, Finnish and English
      mix print_emails sv fi    # just these
  """
  use Mix.Task

  @shortdoc "Print every customer email for review"

  @locales %{"sv" => "sv-FI", "fi" => "fi", "en" => "en-GB"}

  @impl Mix.Task
  def run(args) do
    # Rendering needs the endpoint for its URLs, but never a running queue.
    Mix.Task.run("app.config")
    Application.put_env(:edenflowers, Oban, Keyword.put(Application.fetch_env!(:edenflowers, Oban), :testing, :manual))
    Mix.Task.run("app.start")

    for lang <- if(args == [], do: ["sv", "fi", "en"], else: args) do
      locale = Map.get(@locales, lang) || Mix.raise("Unknown language #{lang}, expected sv, fi or en")
      Mix.shell().info("# Every email in #{locale}\n")

      for {email_type, scenario, _builder, email} <- Edenflowers.Email.Previews.all(locale) do
        Mix.shell().info("## #{email_type}: #{scenario}\n\nSubject: #{email.subject}\n\n#{email.text_body}\n")
      end
    end
  end
end

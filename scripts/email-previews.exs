{:ok, _} = Application.ensure_all_started(:localize)
{:ok, _} = Application.ensure_all_started(:phoenix)
{:ok, _} = EdenflowersWeb.Endpoint.start_link(server: false, watchers: [], code_reloader: false)

output_dir = Path.expand("tmp/email-previews")
File.mkdir_p!(output_dir)

for locale <- ["en-GB", "sv", "fi"] do
  previews = Edenflowers.Email.Previews.all(locale)

  sections =
    Enum.map(previews, fn {type, scenario, _builder, email} ->
      """
      ## #{type} — #{scenario}

      Subject: #{email.subject}

      ```text
      #{String.trim(email.text_body)}
      ```
      """
    end)

  path = Path.join(output_dir, "#{locale}.md")

  File.write!(path, [
    "# Customer email previews (#{locale})\n\n",
    "Fictional review data. These emails have not been sent. ",
    "The catalogue covers curated wording scenarios, not every possible combination of data.\n\n",
    Enum.intersperse(sections, "\n")
  ])

  IO.puts("#{length(previews)} scenarios: #{path}")
end

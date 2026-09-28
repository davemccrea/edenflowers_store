defmodule EdenflowersWeb.Admin.TranslationFields do
  @moduledoc """
  Name and description inputs in every store language, for resources using
  AshTranslation. English lives on the resource itself; Swedish and Finnish
  fill `translations`.

  Each language has a button that asks Claude to fill the other languages from
  it. A LiveView using `language_fields/1` wires it up with:

      def handle_event("translate", %{"from" => from}, socket),
        do: {:noreply, TranslationFields.translate(socket, from)}

      def handle_async(:translate, result, socket),
        do: {:noreply, TranslationFields.put_translations(socket, result)}
  """
  use EdenflowersWeb, :html

  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]

  @translations [{:"sv-FI", "Svenska", "sv"}, {:fi, "Suomi", "fi"}]

  # AshPhoenix only builds nested forms for translations that already exist,
  # so a new record (or one missing a language) would render no inputs.
  def add_forms(form) do
    form =
      if form.forms[:translations],
        do: form,
        else: AshPhoenix.Form.add_form(form, "form[translations]", validate?: false)

    Enum.reduce(@translations, form, fn {locale, _, _}, form ->
      if form.forms[:translations].forms[locale],
        do: form,
        else: AshPhoenix.Form.add_form(form, "form[translations][#{locale}]", validate?: false)
    end)
  end

  def translate(socket, from) do
    fields = current_fields(socket.assigns.form)[from]

    if blank?(fields["name"]) do
      put_flash(socket, :error, ~t"Write a name first, then translate it.")
    else
      socket
      |> assign(:translating, from)
      |> start_async(:translate, fn -> claude().translate(fields, from) end)
    end
  end

  def put_translations(socket, {:ok, {:ok, translations}}) do
    fields = Map.merge(current_fields(socket.assigns.form), translations)

    form =
      AshPhoenix.Form.update_params(socket.assigns.form, fn params ->
        params
        |> Map.merge(fields["en-GB"])
        |> Map.put(
          "translations",
          Map.new(@translations, fn {locale, _, _} -> {to_string(locale), fields[to_string(locale)]} end)
        )
      end)

    assign(socket, form: form, translating: nil)
  end

  def put_translations(socket, _failed) do
    socket
    |> assign(:translating, nil)
    |> put_flash(:error, ~t"Translation failed, please try again.")
  end

  # Read from the form rather than its params: an edit form that hasn't been
  # touched yet has no params, only the saved record.
  defp current_fields(%Phoenix.HTML.Form{source: form}) do
    translations = form.forms[:translations].forms

    Map.new(@translations, fn {locale, _, _} -> {to_string(locale), fields(translations[locale])} end)
    |> Map.put("en-GB", fields(form))
  end

  defp fields(form) do
    %{
      "name" => AshPhoenix.Form.value(form, :name),
      "description" => AshPhoenix.Form.value(form, :description)
    }
  end

  defp blank?(value), do: String.trim(value || "") == ""

  defp claude, do: Application.get_env(:edenflowers, :claude_api, Edenflowers.External.ClaudeAPI)

  attr :form, Phoenix.HTML.Form, required: true
  attr :translating, :string, default: nil, doc: "the locale being translated from, while Claude works"

  def language_fields(assigns) do
    assigns = assign(assigns, :translations, @translations)

    ~H"""
    <div class="divide-base-content/8 divide-y">
      <.language label="English" locale="en-GB" translating={@translating}>
        <.input field={@form[:name]} type="text" label={~t"Name"} lang="en" class="input w-full" />
        <.input
          field={@form[:description]}
          type="textarea"
          label={~t"Description"}
          lang="en"
          rows="5"
          class="textarea w-full"
        />
      </.language>
      <.inputs_for :let={translations} field={@form[:translations]}>
        <.language
          :for={{locale, label, lang} <- @translations}
          label={label}
          locale={to_string(locale)}
          translating={@translating}
        >
          <.inputs_for :let={t} field={translations[locale]}>
            <.input field={t[:name]} type="text" label={~t"Name"} lang={lang} class="input w-full" />
            <.input
              field={t[:description]}
              type="textarea"
              label={~t"Description"}
              lang={lang}
              rows="5"
              class="textarea w-full"
            />
          </.inputs_for>
        </.language>
      </.inputs_for>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :locale, :string, required: true
  attr :translating, :string, default: nil
  slot :inner_block, required: true

  defp language(assigns) do
    assigns = assign(assigns, :id, "language-" <> String.downcase(assigns.label))

    ~H"""
    <div role="group" aria-labelledby={@id} class="space-y-3 py-5 first:pt-0 last:pb-0">
      <div class="flex items-center gap-3">
        <h3 id={@id} class="text-base-content font-medium">{@label}</h3>
        <.button
          type="button"
          size="sm"
          phx-click="translate"
          phx-value-from={@locale}
          disabled={@translating != nil}
          title={~t"Fill the other languages from this one"}
        >
          {if @translating == @locale, do: ~t"Translating…", else: ~t"Translate"}
        </.button>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end
end

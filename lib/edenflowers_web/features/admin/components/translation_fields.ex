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
  use EdenflowersWeb, {:html, gettext_domain: "admin"}

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
      |> start_async(:translate, fn -> Edenflowers.External.ClaudeAPI.impl().translate(fields, from) end)
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
    |> put_flash(:error, ~t"Could not translate. Try again in a moment.")
  end

  # Read from the form rather than its params: an edit form that hasn't been
  # touched yet has no params, only the saved record.
  defp current_fields(%Phoenix.HTML.Form{source: form}) do
    # Params without translations drop their forms until the next full submit.
    translations = if form.forms[:translations], do: form.forms[:translations].forms, else: %{}

    Map.new(@translations, fn {locale, _, _} -> {to_string(locale), fields(translations[locale])} end)
    |> Map.put("en-GB", fields(form))
  end

  defp fields(nil), do: %{"name" => nil, "description" => nil}

  defp fields(form) do
    %{
      "name" => AshPhoenix.Form.value(form, :name),
      "description" => AshPhoenix.Form.value(form, :description)
    }
  end

  defp blank?(value), do: String.trim(value || "") == ""

  attr :form, Phoenix.HTML.Form, required: true
  attr :translating, :string, default: nil, doc: "the locale being translated from, while Claude works"

  @doc """
  One tab per language, English open first. A dot marks a language missing its
  name or description. Every tab's inputs stay in the form, hidden, so
  switching tabs never drops a language's params.
  """
  def language_fields(assigns) do
    fields = current_fields(assigns.form)

    languages =
      for {locale, label} <- [
            {"en-GB", "English"} | Enum.map(@translations, fn {l, label, _} -> {to_string(l), label} end)
          ] do
        %{
          locale: locale,
          label: label,
          missing?: blank?(fields[locale]["name"]) or blank?(fields[locale]["description"])
        }
      end

    assigns = assign(assigns, languages: languages, translations: @translations)

    ~H"""
    <div id="language-tabs">
      <div role="tablist" class="tabs tabs-border mb-4">
        <button
          :for={{language, index} <- Enum.with_index(@languages)}
          type="button"
          role="tab"
          id={"language-tab-#{language.locale}"}
          aria-controls={"language-panel-#{language.locale}"}
          aria-selected={to_string(index == 0)}
          class={["tab gap-1.5", index == 0 && "tab-active"]}
          phx-click={show_language(language.locale)}
        >
          {language.label}
          <span :if={language.missing?} class="status status-warning" aria-hidden="true"></span>
          <span :if={language.missing?} class="sr-only">{~t"(missing text)"}</span>
        </button>
      </div>
      <.language locale="en-GB" translating={@translating} hidden={false}>
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
          :for={{locale, _label, lang} <- @translations}
          locale={to_string(locale)}
          translating={@translating}
          hidden={true}
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

  # JS commands survive LiveView patches, so the open tab stays open while typing.
  defp show_language(locale) do
    JS.add_class("hidden", to: "#language-tabs [role=tabpanel]")
    |> JS.remove_class("hidden", to: "#language-panel-#{locale}")
    |> JS.remove_class("tab-active", to: "#language-tabs [role=tab]")
    |> JS.set_attribute({"aria-selected", "false"}, to: "#language-tabs [role=tab]")
    |> JS.add_class("tab-active")
    |> JS.set_attribute({"aria-selected", "true"})
  end

  attr :locale, :string, required: true
  attr :translating, :string, default: nil
  attr :hidden, :boolean, required: true
  slot :inner_block, required: true

  defp language(assigns) do
    ~H"""
    <div
      role="tabpanel"
      id={"language-panel-#{@locale}"}
      aria-labelledby={"language-tab-#{@locale}"}
      class={["space-y-3", @hidden && "hidden"]}
    >
      {render_slot(@inner_block)}
      <.button
        type="button"
        variant="secondary"
        size="sm"
        phx-click="translate"
        phx-value-from={@locale}
        disabled={@translating != nil}
      >
        {if @translating == @locale, do: ~t"Translating…", else: ~t"Translate"}
      </.button>
    </div>
    """
  end
end

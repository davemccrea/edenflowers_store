defmodule EdenflowersWeb.Admin.TranslationFields do
  @moduledoc """
  Name and description inputs in every store language, for resources using
  AshTranslation. English lives on the resource itself; Swedish and Finnish
  fill `translations`.
  """
  use EdenflowersWeb, :html

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

  attr :form, Phoenix.HTML.Form, required: true

  def language_fields(assigns) do
    assigns = assign(assigns, :translations, @translations)

    ~H"""
    <div class="divide-base-content/8 divide-y">
      <.language label="English">
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
        <.language :for={{locale, label, lang} <- @translations} label={label}>
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
  slot :inner_block, required: true

  defp language(assigns) do
    assigns = assign(assigns, :id, "language-" <> String.downcase(assigns.label))

    ~H"""
    <div
      role="group"
      aria-labelledby={@id}
      class="grid grid-cols-1 gap-x-6 gap-y-3 py-5 first:pt-0 last:pb-0 sm:grid-cols-[6rem_minmax(0,1fr)]"
    >
      <h3 id={@id} class="text-base-content font-medium sm:pt-8">{@label}</h3>
      <div class="space-y-3">{render_slot(@inner_block)}</div>
    </div>
    """
  end
end

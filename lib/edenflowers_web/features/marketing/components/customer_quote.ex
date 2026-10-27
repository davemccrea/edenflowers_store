defmodule EdenflowersWeb.Marketing.CustomerQuote do
  @moduledoc """
  A customer quote in its original language, with an English translation shown on `/en`.
  """

  use EdenflowersWeb, :html

  attr :quote, :string, required: true
  attr :lang, :any, required: true
  attr :en, :string, required: true
  attr :name, :string, required: true
  attr :occasion, :any, default: nil

  def customer_quote(assigns) do
    assigns = assign(assigns, :show_en?, Gettext.get_locale(EdenflowersWeb.Gettext) == "en")

    ~H"""
    <figure class="flex flex-col gap-6">
      <div class="flex flex-col gap-3">
        <blockquote lang={@lang} class="font-serif text-balance text-xl leading-snug md:text-2xl">
          {@quote}
        </blockquote>
        <p
          :if={@show_en?}
          class="text-base-content/70 font-serif text-pretty text-lg italic leading-snug"
        >
          {@en}
        </p>
      </div>
      <figcaption class="eyebrow text-base-content/70">
        {@name}<span :if={@occasion}> · {@occasion}</span>
      </figcaption>
    </figure>
    """
  end
end

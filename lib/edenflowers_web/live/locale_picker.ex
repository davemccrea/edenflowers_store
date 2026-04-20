defmodule EdenflowersWeb.LocalePicker do
  use EdenflowersWeb, :live_component

  def mount(socket) do
    locales = [
      {"sv-FI", "Svenska"},
      {"fi", "Suomi"},
      {"en-GB", "English"}
    ]

    {:ok,
     socket
     |> assign(locales: locales)}
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil

  def render(assigns) do
    current_locale = Cldr.get_locale() |> Cldr.to_string()
    assigns = assign(assigns, :current_locale, current_locale)

    ~H"""
    <form
      id={@id}
      phx-change="change"
      phx-target={@myself}
      class={["group inline-flex items-center gap-1", @class]}
    >
      <select
        name="cldr_locale"
        aria-label={gettext("Language")}
        class="locale-picker text-base-content cursor-pointer bg-transparent text-sm group-hover:text-base-content/60"
      >
        <button>
          <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
          <selectedcontent></selectedcontent>
        </button>
        <option
          :for={{cldr_locale, name} <- @locales}
          value={cldr_locale}
          selected={cldr_locale == @current_locale}
        >
          {name}
        </option>
      </select>
    </form>
    """
  end

  def handle_event("change", %{"cldr_locale" => cldr_locale}, socket) do
    # Redirect to locale controller, which uses the referer header to navigate back
    {:noreply, redirect(socket, to: ~p"/cldr_locale/#{cldr_locale}")}
  end
end

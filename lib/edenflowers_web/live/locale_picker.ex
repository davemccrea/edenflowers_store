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
  attr :dropdown_class, :string, default: "dropdown"
  attr :trigger_class, :string, default: nil
  slot :inner_block, required: true

  def render(assigns) do
    ~H"""
    <details
      id={@id}
      class={@dropdown_class}
      phx-click-away={JS.remove_attribute("open", to: "##{@id}")}
      phx-window-keydown={JS.remove_attribute("open", to: "##{@id}")}
      phx-key="Escape"
    >
      <summary class={["inline-flex list-none items-center gap-1", @trigger_class]}>
        {render_slot(@inner_block)}
      </summary>
      <ul class="menu dropdown-content bg-base-100 border-base-300 z-50 w-40 rounded-none border p-1 shadow">
        <li :for={{cldr_locale, name} <- @locales}>
          <button type="button" phx-target={@myself} phx-click="click" value={cldr_locale}>
            {name}
          </button>
        </li>
      </ul>
    </details>
    """
  end

  def handle_event("click", %{"value" => cldr_locale}, socket) do
    # Redirect to locale controller, which uses the referer header to navigate back
    {:noreply, redirect(socket, to: ~p"/cldr_locale/#{cldr_locale}")}
  end
end

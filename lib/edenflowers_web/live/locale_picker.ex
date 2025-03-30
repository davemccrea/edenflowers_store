defmodule EdenflowersWeb.LocalePicker do
  use EdenflowersWeb, :live_component

  def mount(socket) do
    locales = [
      {"sv", "Svenska"},
      {"fi", "Suomi"},
      {"en", "English"}
    ]

    {:ok,
     socket
     |> assign(locales: locales)}
  end

  def render(assigns) do
    ~H"""
    <sl-dropdown id={@id}>
      <div slot="trigger">
        {render_slot(@inner_block)}
      </div>
      <sl-menu>
        <sl-menu-item :for={{cldr_locale, name} <- @locales} phx-target={@myself} phx-click="click" value={cldr_locale}>
          {name}
        </sl-menu-item>
      </sl-menu>
    </sl-dropdown>
    """
  end

  def handle_event("click", %{"value" => cldr_locale}, socket) do
    {:noreply, redirect(socket, to: ~p"/cldr_locale/#{cldr_locale}")}
  end
end

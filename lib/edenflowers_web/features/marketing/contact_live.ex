defmodule EdenflowersWeb.Marketing.ContactLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="grid gap-12 md:grid-cols-2 md:gap-x-24">
          <div>
            <h1 class="page-title mb-6">{~t"Contact"}</h1>
            <p class="text-base-content/80 text-lg leading-relaxed">
              {~t"Got a question, a special request, or want to talk through an arrangement? Reach us by email or phone, or stop by the shop during opening hours."}
            </p>
          </div>

          <dl class="grid gap-10">
            <.contact_item label={~t"Email"}>
              <a class="link-underline-static-body" href="mailto:info@edenflowers.fi">info@edenflowers.fi</a>
            </.contact_item>

            <.contact_item label={~t"Phone"}>
              <a class="link-underline-static-body" href="tel:+358402209494">040 220 9494</a>
            </.contact_item>

            <.contact_item label={~t"Address"}>
              <address class="not-italic">
                Minimossen<br />
                {~t"Myrvägen 1"}<br />
                {~t"65230 Vasa"}
              </address>
            </.contact_item>

            <.contact_item label={~t"Opening hours"}>
              {~t"Mon–Fri: 09:00–17:00"}<br />
              {~t"Sat: 10:00–15:00"}<br />
              {~t"Sun: closed"}
            </.contact_item>
          </dl>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp contact_item(assigns) do
    ~H"""
    <div class="space-y-2">
      <dt class="eyebrow text-base-content/60">{@label}</dt>
      <dd class="text-lg leading-relaxed">{render_slot(@inner_block)}</dd>
    </div>
    """
  end
end

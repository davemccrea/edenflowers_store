defmodule EdenflowersWeb.Marketing.ContactLive do
  @moduledoc """
  Public contact page with the shop's address and opening details.
  """

  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Business

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: ~t"Contact",
       alternates: alternates("/#{language}/contact"),
       page_description:
         ~t"Get in touch with Eden Flowers in Vaasa about an order, a wedding or a funeral, or visit the shop in Minimossen at Myrvägen 1.",
       json_ld: Business.florist()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      alternates={@alternates}
    >
      <.container>
        <div class="grid gap-12 md:grid-cols-2 md:gap-x-24">
          <div>
            <.image
              src="local:///jennie_1.jpg"
              alt="Jennie"
              width={112}
              height={112}
              sizes="7rem"
              crop="1800:1800:fp:0.35:0.3"
              class="size-28 mb-8 rounded-full object-cover"
            />
            <h1 class="page-title mb-6">{~t"Contact"}</h1>
            <p class="text-base-content/80 text-lg leading-relaxed">
              {~t"Send me an email or give me a call and I'll gladly help."}
            </p>
            <p class="text-base-content/80 mt-4 text-lg leading-relaxed">
              {~t"Have a question?"}
              <.link navigate={~q"/#{language}/faq"} class="link-underline-static-body whitespace-nowrap">
                {~t"See the FAQ"}
              </.link>
            </p>
          </div>

          <dl class="grid gap-10">
            <.contact_item label={~t"Email"}>
              <a class="link-underline-static-body" href={"mailto:#{Business.email()}"}>{Business.email()}</a>
            </.contact_item>

            <.contact_item label={~t"Phone"}>
              <a class="link-underline-static-body" href={"tel:#{Business.phone()}"}>{Business.phone_display()}</a>
            </.contact_item>

            <.contact_item label={~t"Address"}>
              <address class="not-italic">
                <a
                  class="link-underline-static-body"
                  href={Business.maps_url()}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Minimossen<br />
                  {Business.street_address()}<br />
                  {Business.postal_town()}
                </a>
              </address>
            </.contact_item>

            <.contact_item label={~t"Opening hours"}>
              <p :for={line <- Business.opening_hours_lines()}>{line}</p>
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
      <dt class="eyebrow text-base-content/65">{@label}</dt>
      <dd class="text-lg leading-relaxed">{render_slot(@inner_block)}</dd>
    </div>
    """
  end
end

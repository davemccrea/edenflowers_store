defmodule EdenflowersWeb.Marketing.ContactLive do
  @moduledoc """
  Public contact page with the shop's address and opening details.
  """

  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Business
  alias EdenflowersWeb.Marketing.ContactDrawer

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
        <div class="grid items-center gap-8 md:grid-cols-2 md:gap-16 lg:gap-24">
          <figure class="md:order-last md:justify-self-end">
            <.image
              src="local:///profile.jpg"
              alt={~t"Jennie, owner of Eden Flowers"}
              width={800}
              height={1000}
              sizes="(min-width: 768px) 28rem, 8rem"
              crop="2400:3000:fp:0.49:0.62"
              sources={[%{media: "(max-width: 767px)", width: 256, height: 256, crop: "1600:1600:fp:0.49:0.57"}]}
              priority
              class="size-32 rounded-full object-cover md:aspect-[4/5] md:size-auto md:w-full md:max-w-md md:rounded-none"
            />
          </figure>

          <div>
            <h1 class="page-title mb-6">{~t"Contact"}</h1>
            <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
              {~t"Send me a message or give me a call and I'll gladly help."}
            </p>
            <p class="text-base-content/80 mt-4 text-lg leading-relaxed">
              {~t"Have a question?"}
              <.link navigate={~q"/#{language}/faq"} class="link-underline-static-body whitespace-nowrap">
                {~t"See the FAQ"}
              </.link>
            </p>
            <.button phx-click={ContactDrawer.open()} variant="primary" class="mt-8 mb-12">
              {~t"Send me a message"}
            </.button>

            <dl class="grid gap-10 sm:grid-cols-2 sm:gap-x-12 md:grid-cols-1 lg:grid-cols-2">
              <.contact_item label={~t"Email"}>
                <a class="link-underline-static-body touch-target" href={"mailto:#{Business.email()}"}>{Business.email()}</a>
              </.contact_item>

              <.contact_item label={~t"Phone"}>
                <a class="link-underline-static-body touch-target" href={"tel:#{Business.phone()}"}>{Business.phone_display()}</a>
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
                    <span class="sr-only">{~t"(opens a map in a new tab)"}</span>
                  </a>
                </address>
              </.contact_item>

              <.contact_item label={~t"Opening hours"}>
                <p :for={line <- Business.opening_hours_lines()}>{line}</p>
              </.contact_item>
            </dl>
          </div>
        </div>
      </.container>

      <.live_component module={ContactDrawer} id="contact-drawer" />
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp contact_item(assigns) do
    ~H"""
    <div class="space-y-2">
      <dt class="eyebrow text-base-content/70">{@label}</dt>
      <dd class="font-serif text-xl leading-snug">{render_slot(@inner_block)}</dd>
    </div>
    """
  end
end

defmodule EdenflowersWeb.Marketing.TrustedBy do
  @moduledoc """
  The ruled row of client logos on the home and about pages.
  """

  use EdenflowersWeb, :html

  def trusted_by(assigns) do
    assigns = assign(assigns, :clients, clients())

    ~H"""
    <section class="not-last:border-b">
      <div class="container py-12 md:py-16">
        <p class="eyebrow text-base-content/70 mb-8 text-center">{~t"Trusted by"}</p>
        <ul class="flex flex-wrap items-center justify-center gap-x-16 gap-y-10 md:gap-x-24">
          <li :for={client <- @clients}>
            <a
              href={client.url}
              class="touch-target block"
              target="_blank"
              rel="noopener noreferrer"
              aria-label={client.name}
            >
              <img
                src={client.logo}
                alt={client.name}
                width={client.width}
                height={client.height}
                loading="lazy"
                decoding="async"
                class={[client.class, "w-auto opacity-50 grayscale transition-opacity hover:opacity-70"]}
              />
            </a>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  defp clients do
    [
      %{
        name: "Dermosil",
        url: "https://www.dermosil.com/",
        logo: "/images/logo-dermosil.svg",
        width: 230,
        height: 33,
        class: "h-7"
      },
      %{name: "SFP RKP", url: "https://sfp.fi/", logo: "/images/logo-sfp.svg", width: 182, height: 40, class: "h-8"},
      %{
        name: ~t"Evangelical Lutheran Church of Finland",
        url: "https://evl.fi/en/",
        logo: "/images/logo-evl.svg",
        width: 363,
        height: 81,
        class: "h-8"
      },
      %{
        name: "Bonnier News Finland",
        url: "https://bnf.fi/",
        logo: "/images/logo-bonnier-news.png",
        width: 104,
        height: 32,
        class: "h-8"
      }
    ]
  end
end

defmodule EdenflowersWeb.Marketing.AboutLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <section class="flex flex-col gap-12 md:flex-row md:items-center md:gap-16 lg:gap-24">
          <div class="text-base-content/80 flex max-w-2xl flex-col gap-6 text-lg leading-relaxed">
            <h1 class="page-title text-base-content mb-4">{~t"About"}</h1>
            <p>
              {~t"Hi, I'm Jennie! I've run Eden Flowers in Vaasa since 2018. You'll find the shop in Minimossen, the recycling mall at Myrvägen 1."}
            </p>
            <p>
              {~t"Drop by for ready-made bouquets, houseplants, and second-hand pots and vases. For anything made to order,"}
              <.link navigate={~p"/contact"} class="link-underline-static-body">{~t"get in touch"}</.link>.
            </p>
            <p>
              {~t"I make flowers for every occasion: christenings, weddings, funerals and everything in between. Whether it's for your own home or for a friend, ordering should be easy, so"}
              <.link navigate={~p"/store"} class="link-underline-static-body">{~t"order online"}</.link>
              {~t"or just pop in."}
            </p>
          </div>

          <div class="w-full flex-shrink-0 md:w-80 lg:w-96">
            <.image
              src="local:///jennie_pregnant.jpg"
              alt="Jennie"
              width={800}
              height={1000}
              sizes="(min-width: 1024px) 24rem, (min-width: 768px) 20rem, 100vw"
              class="aspect-[4/5] w-full rounded-md object-cover"
            />
          </div>
        </section>
      </.container>
    </Layouts.app>
    """
  end
end

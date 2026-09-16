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
        <h1 class="page-title hero-reveal mb-16 md:mb-20">{~t"About"}</h1>

        <div class="flex flex-col gap-12 md:flex-row md:gap-16 lg:gap-24">
          <div class="w-full flex-shrink-0 md:w-80 lg:w-96">
            <.image
              src="local:///jennie_pregnant.jpg"
              alt="Jennie"
              width={800}
              height={1000}
              sizes="(min-width: 1024px) 24rem, (min-width: 768px) 20rem, 100vw"
              class="aspect-[4/5] w-full object-cover"
            />
          </div>

          <div class="text-base-content/80 flex max-w-2xl flex-col gap-6 text-lg leading-relaxed">
            <h2 class="section-title text-base-content sm:text-4xl">{~t"Hello, I'm Jennie"}</h2>
            <p>
              Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
            </p>
            <p>
              Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
            </p>
            <div class="pt-2">
              <.button navigate={~p"/contact"} variant="primary">
                {~t"Get in touch"}
              </.button>
            </div>
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end
end

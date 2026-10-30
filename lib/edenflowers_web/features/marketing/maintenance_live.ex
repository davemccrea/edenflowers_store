defmodule EdenflowersWeb.Marketing.MaintenanceLive do
  @moduledoc """
  Page shown while the storefront is in maintenance mode.
  """

  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Business

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-200 flex min-h-screen flex-col">
      <header class="flex justify-center py-8">
        <img src={~p"/images/logo-eden-flowers.svg"} alt="Eden Flowers" width="160" height="80" class="w-40 md:hidden" />
        <img
          src={~p"/images/logo-eden-flowers-wide.svg"}
          alt="Eden Flowers"
          width="256"
          height="80"
          class="hidden w-64 md:block"
        />
      </header>

      <main
        id="main-content"
        tabindex="-1"
        class="flex flex-grow items-center justify-center px-6 py-8 outline-hidden md:-mt-24"
      >
        <div class="text-base-content flex max-w-xl flex-col gap-5 text-center text-lg">
          <p lang="sv">Vi uppdaterar webbplatsen och är tillbaka om en stund.</p>
          <p lang="fi">Päivitämme verkkosivuja ja palaamme hetken kuluttua.</p>
          <p lang="en">We're updating the website and will be back in a moment.</p>
          <p class="mt-4 flex flex-col gap-1">
            <a href={"mailto:#{Business.email()}"} class="link-underline-static-body">{Business.email()}</a>
            <a href={"tel:#{Business.phone()}"} class="link-underline-static-body whitespace-nowrap">
              {Business.phone_display()}
            </a>
          </p>
        </div>
      </main>
    </div>
    """
  end
end

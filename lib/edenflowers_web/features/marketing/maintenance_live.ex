defmodule EdenflowersWeb.Marketing.MaintenanceLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-base-200 flex min-h-screen flex-col">
      <header class="flex justify-center py-8">
        <.image
          src="local:///Eden_flowers-logo1_green_web.svg"
          alt="Eden Flowers"
          width={160}
          height={80}
          class="w-40 md:hidden"
        />
        <.image
          src="local:///Eden_flowers-logo2_green_web.svg"
          alt="Eden Flowers"
          width={256}
          height={80}
          class="hidden w-64 md:block"
        />
      </header>

      <main
        id="main-content"
        tabindex="-1"
        class="flex flex-grow items-center justify-center px-6 py-8 outline-hidden md:-mt-24"
      >
        <div class="text-base-content flex max-w-xl flex-col gap-5 text-center text-lg">
          <p>
            Vi håller på att förnya webbplatsen. Kontakta Jennie på
            <a href="mailto:info@edenflowers.fi" class="link-underline-static-body">info@edenflowers.fi</a>
            eller <a href="tel:+358402209494" class="link-underline-static-body whitespace-nowrap">040 220 9494</a>.
          </p>
          <p>
            Uudistamme verkkosivujamme. Ota yhteyttä Jennieen:
            <a href="mailto:info@edenflowers.fi" class="link-underline-static-body">info@edenflowers.fi</a>
            tai <a href="tel:+358402209494" class="link-underline-static-body whitespace-nowrap">040 220 9494</a>.
          </p>
        </div>
      </main>
    </div>
    """
  end
end

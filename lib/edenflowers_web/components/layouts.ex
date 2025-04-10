defmodule EdenflowersWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use EdenflowersWeb, :controller` and
  `use EdenflowersWeb, :live_view`.
  """
  use EdenflowersWeb, :html

  embed_templates "layouts/*"

  def app(assigns) do
    locale = Cldr.get_locale()
    {:ok, locale_name} = Edenflowers.Cldr.Language.to_string(locale)

    assigns =
      assigns
      |> assign(
        nav: [
          {~p"/#store", gettext("Store")},
          {~p"/courses", gettext("Courses")},
          {~p"/weddings", gettext("Weddings")},
          {~p"/condolences", gettext("Condolences")},
          {~p"/about", gettext("About")},
          {~p"/contact", gettext("Contact")}
        ]
      )
      |> assign(locale_name: String.capitalize(locale_name))

    ~H"""
    <%!-- Nav drawer --%>
    <sl-drawer id="nav-drawer" placement="start" no-header="true">
      <div class="bg-base-200 flex h-full flex-col">
        <header class="bg-accent-2 flex flex-row items-center justify-between pt-8 pr-4 pl-8">
          <.link
            navigate={~p"/"}
            class="text-primary font-sans whitespace-nowrap font-bold uppercase tracking-widest sm:text-2xl"
          >
            Eden Flowers
          </.link>

          <button type="button" phx-click={JS.dispatch("hide-nav")} class="h-12 w-12 cursor-pointer">
            <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
          </button>
        </header>

        <div class="flex flex-1 flex-col justify-between p-8">
          <nav>
            <ul class="space-y-4">
              <li :for={{url, name} <- @nav}>
                <.link
                  class="font-serif text-base-content text-2xl hover:decoration-(--color-accent-alt) hover:underline hover:underline-offset-4 sm:text-3xl"
                  phx-click={JS.dispatch("hide-nav")}
                  navigate={url}
                >
                  {name}
                </.link>
              </li>
            </ul>
          </nav>
        </div>

        <footer class="bg-base-300 flex flex-col px-8 py-8">
          <%!-- TODO: what else should go here? --%>
          <.social_media_links size={6} />
        </footer>
      </div>
    </sl-drawer>

    <sl-drawer id="cart-drawer" placement="end" no-header="true">
      <div class="bg-base-200 flex h-full flex-col">
        <header class="bg-accent-2 flex flex-row items-center justify-between pt-8 pr-4 pl-8">
          <h1 class="font-serif text-3xl">{gettext("Cart")}</h1>

          <button phx-click={JS.dispatch("hide-cart")} type="button" class="h-12 w-12 cursor-pointer">
            <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
          </button>
        </header>

        <div class="flex flex-1 flex-col justify-between p-8">
          <p>Your cart is empty.</p>
        </div>

        <footer class="bg-base-300 flex flex-col px-8 py-8">
          <.link navigate={~p"/checkout"} phx-click={JS.dispatch("hide-cart")} class="btn btn-primary">
            {gettext("Checkout")}
          </.link>
        </footer>
      </div>
    </sl-drawer>

    <hotfx-shy-header>
      <header class="w-full">
        <%!-- Banner --%>
        <section class="border-b bg-sky-100 py-2 text-center">
          <span class="text-accent-content text-sm">{gettext("Let us know what you think of the new website! 🚀")}</span>
        </section>

        <%!-- Main header --%>
        <section class="bg-base-100 border-b px-3 py-2 sm:px-6 sm:py-4">
          <div class="flex items-center">
            <%!-- Left --%>
            <div class="flex flex-1 justify-start">
              <%!-- Mobile hamburger menu --%>
              <div class="block xl:hidden">
                <button phx-click={JS.dispatch("show-nav")} type="button" class="h-12 w-12 cursor-pointer">
                  <.icon name="hero-bars-3-bottom-left" class="text-base-content h-6 w-6 hover:text-base-content/60" />
                </button>
              </div>

              <%!-- Desktop navigation --%>
              <nav class="hidden xl:block">
                <ul class="flex gap-3">
                  <li :for={{url, name} <- @nav}>
                    <.link
                      class="text-base-content whitespace-nowrap text-sm hover:underline hover:underline-offset-2"
                      navigate={url}
                    >
                      {name}
                    </.link>
                  </li>
                </ul>
              </nav>
            </div>

            <%!-- Centre --%>
            <div class="flex flex-1 flex-col items-center">
              <%!-- Logo --%>
              <.link
                navigate={~p"/"}
                class="text-primary font-sans whitespace-nowrap text-xl font-bold uppercase tracking-widest sm:text-2xl"
              >
                Eden Flowers
              </.link>
            </div>

            <%!-- Right --%>
            <div class="flex flex-1 items-center justify-end sm:gap-4">
              <%!-- Locale picker button --%>
              <.live_component id="locale-picker-header" module={EdenflowersWeb.LocalePicker}>
                <button class="group h-12 w-12 cursor-pointer sm:h-auto sm:w-auto">
                  <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
                  <span class="text-base-content hidden text-sm group-hover:text-base-content/60 sm:inline-flex">
                    {@locale_name}
                  </span>
                </button>
              </.live_component>

              <%!-- Cart button --%>
              <button
                phx-click={JS.dispatch("show-cart")}
                type="button"
                class="group h-12 w-12 cursor-pointer sm:h-auto sm:w-auto"
              >
                <.icon class="text-base-content h-5 w-5 group-hover:text-base-content/60" name="hero-shopping-bag" />
                <span class="text-base-content hidden text-sm group-hover:text-base-content/60 sm:inline-flex">
                  {gettext("Cart")}
                </span>
              </button>
            </div>
          </div>
        </section>
      </header>
    </hotfx-shy-header>

    <main class="flex-grow">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>

    <footer>
      <div class="border-t border-b bg-pink-100">
        <div class="container py-12 md:py-24">
          <div class="flex flex-col gap-8 md:flex-row">
            <div class="m-auto flex-1">
              <div class="m-auto max-w-lg space-y-4">
                <h2 class="font-serif text-2xl sm:text-3xl">
                  {gettext("Enjoy 20% off your next order and get occassional floral advice in your inbox.")}
                </h2>

                <.form for={to_form(%{})}>
                  <input type="text" class="input input-lg w-full text-sm" placeholder="Email Address" name="email_address" />
                </.form>
              </div>
            </div>

            <div class="flex-1">
              <div class="m-auto max-w-lg">
                <.social_media_links size={6} />
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-col items-center gap-4 py-8">
        <.live_component id="locale-picker-footer" module={EdenflowersWeb.LocalePicker}>
          <button class="group cursor-pointer">
            <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
            <span class="text-base-content inline-flex text-sm group-hover:text-base-content/60">
              {@locale_name}
            </span>
          </button>
        </.live_component>

        <span class="text-xs">
          © Eden Flowers {DateTime.now!("Europe/Helsinki") |> Map.get(:year)} •
          <a
            class="text-base-content whitespace-nowrap hover:underline hover:underline-offset-2"
            href="https://github.com/davemccrea/edenflowers_store"
          >
            Built with <span>❤️</span>
          </a>
        </span>
      </div>
    </footer>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end

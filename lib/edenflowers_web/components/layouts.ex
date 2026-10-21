defmodule EdenflowersWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EdenflowersWeb, :html

  alias EdenflowersWeb.Business

  embed_templates "layouts/*"

  attr :conn, Plug.Conn, required: true
  attr :alternates, :map, required: true

  def hreflang_links(assigns) do
    ~H"""
    <link
      :for={{code, path} <- @alternates}
      rel="alternate"
      hreflang={code |> String.split("-") |> hd()}
      href={Phoenix.VerifiedRoutes.unverified_url(@conn, path)}
    />
    <link rel="alternate" hreflang="x-default" href={url(~p"/")} />
    """
  end

  attr :data, :map, required: true

  def json_ld(assigns) do
    ~H"""
    <script type="application/ld+json">
      <%= raw(Jason.encode!(@data, escape: :html_safe)) %>
    </script>
    """
  end

  attr :id, :string, required: true
  attr :current_path, :string, required: true
  attr :alternates, :map, default: %{}, doc: "the page in each language, for pages with a URL per language"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def locale_picker(assigns) do
    current_language = Localize.get_locale().language |> to_string()

    locales =
      for code <- Edenflowers.Locales.all() do
        language_code = code |> String.split("-") |> hd()
        name = Localize.Language.display_name!(language_code, locale: code, fallback: true)
        {code, String.capitalize(name), language_code == current_language}
      end

    assigns = assign(assigns, :locales, locales)

    # A transparent native <select> laid over the slot, so the slot is what
    # shows and the browser's own picker is what opens. The focus outline is
    # in layout.css (.locale-picker).
    ~H"""
    <span class={["locale-picker group relative inline-block", @class]}>
      <span aria-hidden="true">{render_slot(@inner_block)}</span>
      <select
        id={@id}
        aria-label={~t"Language"}
        onpointerdown="this.dataset.pointer = ''"
        onkeydown="delete this.dataset.pointer"
        onblur="delete this.dataset.pointer"
        onchange="this.blur(); window.location.href = this.value"
        class="min-h-11 min-w-11 absolute top-1/2 left-1/2 h-full w-full -translate-x-1/2 -translate-y-1/2 cursor-pointer opacity-0"
      >
        <option
          :for={{code, name, current?} <- @locales}
          value={@alternates[code] || ~p"/locale/#{code}?redirect_to=#{@current_path}"}
          selected={current?}
        >
          {name}
        </option>
      </select>
    </span>
    """
  end

  attr :current_path, :string, required: true
  attr :alternates, :map, default: %{}
  attr :current_locale, :string, required: true

  defp footer_locale_picker(assigns) do
    ~H"""
    <.locale_picker id="locale-picker-footer" current_path={@current_path} alternates={@alternates}>
      <span class="group inline-flex cursor-pointer items-center gap-1">
        <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
        <span class="text-base-content inline-flex text-sm group-hover:text-base-content/60">
          {@current_locale}
        </span>
      </span>
    </.locale_picker>
    """
  end

  defp sign_in_href(current_path) do
    case EdenflowersWeb.Auth.ReturnTo.safe_path(current_path) do
      nil -> ~p"/sign-in"
      "/" -> ~p"/sign-in"
      path -> ~p"/sign-in?return_to=#{path}"
    end
  end

  defp admin_path?(path), do: path == "/admin" or String.starts_with?(path, "/admin/")

  @doc """
  Renders the page's flash notices plus the connection-lost toasts, which
  LiveView reveals on disconnect and hides again on reconnect.

  Toasts sit at the bottom so they never cover the header's cart and account
  controls, and stack in one container instead of overlapping.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div
      id="flash-group"
      aria-live="polite"
      class="toast bottom-[calc(1rem+env(safe-area-inset-bottom))] z-50 max-sm:inset-x-4 max-sm:w-auto sm:end-6 sm:bottom-[calc(1.5rem+env(safe-area-inset-bottom))]"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={~t"Connection lost"}
        phx-disconnected={show("#client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {~t"Reconnecting…"}
        <.icon name="hero-arrow-path" class="size-3 align-[-0.125em] ml-1 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    current_locale = Localize.Language.display_name!(Localize.get_locale().language, fallback: true)

    assigns =
      assigns
      |> assign(current_locale: String.capitalize(current_locale))

    ~H"""
    <.flash_group flash={@flash} />

    <div class="bg-base-200 flex min-h-screen flex-col">
      <%!-- Mirrors the storefront header's padding and row height so the wordmark doesn't shift between pages --%>
      <header class="px-3 py-2 sm:px-6 sm:py-4">
        <div class="flex h-12 items-center justify-center xl:h-10">
          <.link
            navigate={~q"/#{language}"}
            class="text-primary logo-wordmark touch-target whitespace-nowrap text-xl max-sm:tracking-[0.1em] sm:text-2xl lg:text-3xl"
          >
            Eden Flowers
          </.link>
        </div>
      </header>

      <main id="main-content" tabindex="-1" class="flex flex-grow items-center justify-center outline-hidden">
        {render_slot(@inner_block)}
      </main>

      <footer class="py-8 text-center">
        <.footer_locale_picker current_path={@current_path} current_locale={@current_locale} />
      </footer>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :current_path, :string, required: true
  attr :current_user, :map, required: true

  attr :fill_viewport, :boolean,
    default: false,
    doc: "pins the page to the window height so the content manages its own scrolling"

  slot :inner_block, required: true

  def admin(assigns) do
    nav_sections = [
      {nil, [{~p"/admin", ~t"Overview", true, "hero-squares-2x2"}]},
      {~t"Sales",
       [
         {~p"/admin/orders", ~t"Orders", true, "hero-shopping-bag"},
         {~p"/admin/subscriptions", ~t"Subscriptions", true, "hero-arrow-path"},
         {~p"/admin/customers", ~t"Customers", true, "hero-users"}
       ]},
      {~t"Shop",
       [
         {~p"/admin/products", ~t"Products", true, "hero-gift"},
         {~p"/admin/courses", ~t"Courses", true, "hero-academic-cap"},
         {EdenflowersWeb.Admin.PromotionsLive.default_path(), ~t"Promotions", true, "hero-receipt-percent"},
         {~p"/admin/fulfillments", ~t"Delivery and pickup", true, "hero-calendar-days"}
       ]},
      {~t"Marketing", [{"https://app.brevo.com", "Brevo", false, "hero-paper-airplane"}]},
      {~t"Finances", [{~p"/admin/expenses", ~t"Expenses", true, "hero-banknotes"}]}
    ]

    system_nav = [
      {~p"/admin/emails", ~t"Email previews", true, "hero-envelope"},
      {"/admin/errors", ~t"Errors", false, "hero-exclamation-triangle"},
      {"/admin/oban", "Oban", false, "hero-cpu-chip"},
      {"/admin/ash", "AshAdmin", false, "hero-circle-stack"}
    ]

    assigns =
      assigns
      |> assign(:nav_sections, nav_sections)
      |> assign(:system_nav, system_nav)

    ~H"""
    <.flash_group flash={@flash} />

    <div
      id="admin-app"
      phx-hook="AdminApp"
      class={["admin-theme", if(@fill_viewport, do: "h-dvh flex flex-col lg:flex-row", else: "min-h-screen lg:flex")]}
    >
      <%!-- Mobile: slide-in drawer --%>
      <.drawer
        id="admin-nav-drawer"
        placement="left"
        label={~t"Admin navigation"}
        class="bg-base-200 border-base-content/20 w-[80vw] flex h-full flex-col border-r sm:w-[25rem]"
      >
        <.admin_sidebar_content
          nav_sections={@nav_sections}
          system_nav={@system_nav}
          current_path={@current_path}
          closeable={true}
        />
      </.drawer>

      <%!-- Desktop: persistent sidebar, pinned so it stays in view while content scrolls --%>
      <aside
        aria-label={~t"Admin navigation"}
        class="admin-sidebar [view-transition-name:admin-sidebar] bg-base-200 border-base-content/20 hidden border-r lg:sticky lg:top-0 lg:flex lg:h-screen lg:w-64 lg:shrink-0 lg:flex-col"
      >
        <.admin_sidebar_content
          nav_sections={@nav_sections}
          system_nav={@system_nav}
          current_path={@current_path}
          closeable={false}
        />
      </aside>

      <div class={["flex min-w-0 flex-1 flex-col", @fill_viewport && "min-h-0"]}>
        <%!-- Mobile topbar mirrors the store header's menu button and wordmark.
             Equal side columns keep the wordmark centred on the bar.
             It reaches up under the status bar and stays pinned there: iOS standalone draws a glass
             blur over the top edge unless a sticky or fixed element covers it. --%>
        <div class="[view-transition-name:admin-topbar] grid-cols-[5rem_1fr_5rem] bg-base-200 border-base-content/12 -mt-[env(safe-area-inset-top)] pt-[calc(env(safe-area-inset-top)+0.5rem)] sticky top-0 z-30 grid items-center border-b px-3 pb-2 sm:px-6 lg:hidden">
          <div class="flex items-center">
            <button
              type="button"
              class="flex h-12 w-12 items-center justify-center"
              phx-click={JS.exec("phx-show", to: "#admin-nav-drawer")}
              aria-label={~t"Open navigation menu"}
            >
              <.icon name="hero-bars-3-bottom-left" class="text-base-content h-6 w-6 hover:text-base-content/60" />
            </button>
          </div>
          <.link
            navigate={~p"/admin"}
            class="text-primary logo-wordmark touch-target justify-self-center whitespace-nowrap text-xl max-sm:tracking-[0.1em] sm:text-2xl"
          >
            Eden Flowers
          </.link>
          <div class="justify-self-end">
            <.admin_account_menu current_user={@current_user} compact={true} />
          </div>
        </div>

        <div class="[view-transition-name:admin-search] border-base-content/12 border-b px-4 py-2 lg:hidden">
          <.admin_search id="admin-search-mobile" />
        </div>

        <%!-- The view-transition name makes this a stacking context, so it needs a z-index for
             the user menu to open over a page's sticky header. --%>
        <div class="[view-transition-name:admin-header] border-base-content/12 relative z-30 hidden items-center justify-between gap-6 border-b px-8 py-3 lg:flex">
          <.admin_search id="admin-search" class="w-full max-w-md" />
          <.admin_account_menu current_user={@current_user} />
        </div>

        <main
          id="main-content"
          tabindex="-1"
          class={["outline-hidden", if(@fill_viewport, do: "flex min-h-0 flex-1 flex-col", else: "flex-grow pb-12")]}
        >
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :class, :any, default: nil

  defp admin_search(assigns) do
    ~H"""
    <form action={~p"/admin/search"} method="get" role="search" class={["relative", @class]}>
      <label for={@id} class="sr-only">{~t"Search orders and customers"}</label>
      <.icon
        name="hero-magnifying-glass"
        class="text-base-content/50 pointer-events-none absolute top-1/2 left-3 z-10 h-4 w-4 -translate-y-1/2"
      />
      <input
        id={@id}
        type="search"
        name="q"
        data-admin-search
        placeholder={~t"Search orders and customers…"}
        class="input w-full pl-9 lg:input-sm"
      />
      <kbd
        aria-hidden="true"
        class="kbd kbd-sm text-base-content/75 pointer-events-none absolute top-1/2 right-2 z-10 hidden -translate-y-1/2 lg:inline-flex"
      >
        /
      </kbd>
    </form>
    """
  end

  attr :nav_sections, :list, required: true
  attr :system_nav, :list, required: true
  attr :current_path, :string, required: true
  attr :closeable, :boolean, required: true

  defp admin_sidebar_content(assigns) do
    assigns = assign(assigns, :version, "v#{Application.spec(:edenflowers, :vsn)}")

    ~H"""
    <div class="flex h-full flex-col py-5">
      <div class="mb-6 flex items-center justify-between px-5">
        <.link navigate={~p"/admin"} class="text-primary logo-wordmark text-lg">
          Eden Flowers
        </.link>
        <.icon_button
          :if={@closeable}
          phx-click={JS.exec("phx-hide", to: "#admin-nav-drawer")}
          size="sm"
          aria_label={~t"Close navigation menu"}
        >
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </.icon_button>
      </div>

      <nav class="min-h-0 flex-1 space-y-4 overflow-y-auto px-3">
        <div :for={{heading, items} <- @nav_sections} class="space-y-0.5">
          <p :if={heading} class="text-base-content/75 mb-1 px-3 text-xs">{heading}</p>
          <.admin_nav_item
            :for={{path, label, live?, icon} <- items}
            path={path}
            label={label}
            live?={live?}
            icon={icon}
            current_path={@current_path}
            exact={path == "/admin"}
          />
        </div>
      </nav>

      <div class="border-base-content/12 mt-auto border-t px-3 pt-4">
        <p class="text-base-content/75 mb-1 px-3 text-xs">{~t"System"}</p>
        <.admin_nav_item
          :for={{path, label, live?, icon} <- @system_nav}
          path={path}
          label={label}
          live?={live?}
          icon={icon}
          current_path={@current_path}
          exact={false}
        />

        <a
          href={"https://github.com/davemccrea/edenflowers_store/releases/tag/#{@version}"}
          target="_blank"
          rel="noopener"
          class="text-base-content/75 mt-3 block px-3 text-xs hover:text-base-content"
        >
          {@version}
        </a>
      </div>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :live?, :boolean, required: true
  attr :icon, :string, required: true
  attr :current_path, :string, required: true
  attr :exact, :boolean, default: false

  defp admin_nav_item(assigns) do
    external = String.starts_with?(assigns.path, "https://")

    assigns =
      assigns
      |> assign(:external, external)
      |> assign(:active, not external and admin_nav_active?(assigns.current_path, assigns.path, assigns.exact))

    ~H"""
    <.link
      {if @live?, do: [navigate: @path], else: [href: @path]}
      {if @external, do: [target: "_blank", rel: "noopener"], else: []}
      aria-current={@active && "page"}
      class={["flex items-center gap-3 px-3 py-2 text-sm transition-colors", if(@active,
    do: "text-base-content bg-base-300/50 font-medium",
    else: "text-base-content/75 hover:bg-base-300/40 hover:text-base-content")]}
    >
      <.icon name={@icon} class={["h-4 w-4 shrink-0", if(@active, do: "text-primary", else: "text-base-content/60")]} />
      {@label}
    </.link>
    """
  end

  defp admin_nav_active?(current_path, path, exact) do
    # Nav paths may carry default filters in their query string; only the path decides the active item.
    nav_path = URI.parse(path).path

    if exact, do: current_path == nav_path, else: String.starts_with?(current_path, nav_path)
  end

  attr :current_user, :map, required: true
  attr :compact, :boolean, default: false

  defp admin_account_menu(assigns) do
    assigns =
      assigns
      |> assign(:display_name, admin_user_display_name(assigns.current_user))
      |> assign(:email, admin_user_email(assigns.current_user))
      |> assign(:initials, admin_user_initials(assigns.current_user))

    ~H"""
    <div class="dropdown dropdown-end">
      <button
        type="button"
        tabindex="0"
        aria-label={~t"Admin account menu"}
        class={["inline-flex items-center transition-colors hover:bg-base-300/50 focus-visible:outline-solid focus-visible:outline-2 focus-visible:outline-offset-2", if(@compact, do: "touch-target h-9 w-9 justify-center p-0", else: "gap-2 px-2 py-1.5")]}
      >
        <img
          :if={@current_user.avatar_content_type}
          src={~p"/admin/account/avatar"}
          alt=""
          class="h-7 w-7 shrink-0 rounded-full object-cover"
        />
        <span
          :if={!@current_user.avatar_content_type}
          class="bg-primary/10 text-primary inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold"
        >
          {@initials}
        </span>
        <span :if={!@compact} class="min-w-0 text-left">
          <span class="text-base-content max-w-44 block truncate text-sm font-medium">{@display_name}</span>
          <span class="text-base-content/75 max-w-44 block truncate text-xs">{@email}</span>
        </span>
        <.icon :if={!@compact} name="hero-chevron-down" class="text-base-content/60 h-4 w-4 shrink-0" />
      </button>

      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 border-base-content/12 mt-2 w-56 border p-1 shadow"
      >
        <li :if={@compact} class="px-3 py-2">
          <span class="block p-0 hover:bg-transparent">
            <span class="text-base-content block truncate text-sm font-medium">{@display_name}</span>
            <span class="text-base-content/75 block truncate text-xs">{@email}</span>
          </span>
        </li>
        <li :if={@compact}></li>
        <li>
          <.link navigate={~p"/admin/account"}>
            <.icon name="hero-user-circle" class="h-4 w-4" />
            {~t"Account"}
          </.link>
        </li>
        <li>
          <.link href={~q"/#{language}"}>
            <.icon name="hero-building-storefront" class="h-4 w-4" />
            {~t"View store"}
          </.link>
        </li>
        <li>
          <.link href={~p"/sign-out"} method="delete">
            <.icon name="hero-arrow-right-start-on-rectangle" class="h-4 w-4" />
            {~t"Sign out"}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp admin_user_display_name(user) do
    case Map.get(user, :first_name) do
      first_name when is_binary(first_name) ->
        first_name = String.trim(first_name)
        if first_name == "", do: admin_user_email(user), else: first_name

      _ ->
        admin_user_email(user)
    end
  end

  defp admin_user_email(user), do: user |> Map.get(:email) |> to_string()

  defp admin_user_initials(user) do
    case Map.get(user, :initials) do
      initials when is_binary(initials) ->
        initials = String.trim(initials)
        if initials == "", do: fallback_admin_initial(user), else: initials

      _ ->
        fallback_admin_initial(user)
    end
  end

  defp fallback_admin_initial(user),
    do: user |> admin_user_email() |> String.first() |> Kernel.||("A") |> String.upcase()

  attr :current_user, :map, required: true
  attr :flash, :map, required: true
  attr :order, :map, required: true
  attr :current_path, :string, required: true
  attr :alternates, :map, default: %{}
  slot :inner_block, required: true

  def app(assigns) do
    current_locale = Localize.Language.display_name!(Localize.get_locale().language, fallback: true)

    assigns =
      assigns
      |> assign(
        nav: [
          {~q"/#{language}/store", ~t"Store"},
          {~q"/#{language}/courses", ~t"Courses"},
          {~q"/#{language}/weddings", ~t"Weddings"},
          {~q"/#{language}/condolences", ~t"Condolences"},
          {~q"/#{language}/about", ~t"About"},
          {~q"/#{language}/contact", ~t"Contact"}
        ]
      )
      |> assign(current_locale: String.capitalize(current_locale))
      |> assign(current_language_code: Localize.get_locale().language |> to_string() |> String.upcase())

    ~H"""
    <.drawer
      id="nav-drawer"
      placement="left"
      label={~t"Navigation menu"}
      class="bg-base-200 border-r-1 w-[80vw] flex h-full flex-col overflow-y-auto overscroll-contain sm:w-[25rem]"
    >
      <header class="flex flex-row items-center justify-between gap-4 pt-6 pr-4 pl-4 sm:pt-8 sm:pl-8">
        <.link
          navigate={~q"/#{language}"}
          class="text-primary logo-wordmark whitespace-nowrap text-xl sm:text-3xl"
        >
          Eden Flowers
        </.link>

        <.icon_button aria_label={~t"Close navigation menu"} phx-click={JS.exec("phx-hide", to: "#nav-drawer")}>
          <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
        </.icon_button>
      </header>

      <div class="flex flex-1 flex-col justify-between p-4 sm:p-8">
        <nav>
          <ul class="space-y-4">
            <li :for={{url, name} <- @nav}>
              <.link
                class="font-serif text-base-content link-underline-hover text-3xl"
                phx-click={JS.exec("phx-hide", to: "#nav-drawer")}
                navigate={url}
              >
                {name}
              </.link>
            </li>
          </ul>
        </nav>
      </div>

      <footer class="bg-base-300 flex flex-col gap-6 px-8 py-8">
        <.link
          class="text-base-content group flex w-fit items-center gap-2 text-base tracking-wide"
          phx-click={JS.exec("phx-hide", to: "#nav-drawer")}
          navigate={if @current_user, do: ~p"/account"}
          href={unless @current_user, do: sign_in_href(@current_path)}
        >
          <.icon name="hero-user-circle" class="h-5 w-5" />
          <span class="link-underline-hover">
            {if @current_user, do: ~t"Account", else: ~t"Sign In"}
          </span>
        </.link>

        <.social_media_links />
      </footer>
    </.drawer>

    <.live_component
      id="cart-drawer-component"
      module={EdenflowersWeb.Cart.Drawer}
      order={@order}
      current_user={@current_user}
    />

    <div
      id="hotfx-shy-header"
      phx-hook="HotFxShyHeader"
      data-hide={JS.add_class("shy-header--hidden")}
      data-show={JS.remove_class("shy-header--hidden")}
    >
      <header class="w-full">
        <section class="bg-base-100 border-b px-3 py-2 sm:px-6 sm:py-4">
          <div class="grid-cols-[1fr_auto_1fr] grid items-center xl:gap-x-8">
            <div class="flex items-center justify-start">
              <div class="flex xl:hidden">
                <button
                  type="button"
                  class="flex h-12 w-12 items-center justify-center"
                  aria-label={~t"Open navigation menu"}
                  aria-controls="nav-drawer"
                  aria-expanded="false"
                  phx-click={JS.exec("phx-show", to: "#nav-drawer")}
                >
                  <.icon name="hero-bars-3-bottom-left" class="text-base-content h-6 w-6 hover:text-base-content/60" />
                </button>
              </div>

              <%!-- Sits beside the menu button below lg because the right side is already wider, which pushes the logo off-centre --%>
              <.link
                :if={@current_user && @current_user.admin}
                id="admin-shortcut-compact"
                href={~p"/admin"}
                aria-label="Admin"
                class="touch-target group flex h-12 w-8 items-center justify-center lg:hidden"
              >
                <.icon name="hero-squares-2x2" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
              </.link>

              <nav class="hidden xl:block">
                <ul class="flex gap-6">
                  <li :for={{url, name} <- @nav}>
                    <.link
                      class="text-base-content link-underline-hover whitespace-nowrap text-sm tracking-wide"
                      navigate={url}
                    >
                      {name}
                    </.link>
                  </li>
                </ul>
              </nav>
            </div>

            <div class="flex items-center justify-center">
              <.link
                navigate={~q"/#{language}"}
                class="text-primary logo-wordmark touch-target whitespace-nowrap text-xl max-sm:tracking-[0.1em] sm:text-2xl lg:text-3xl"
              >
                Eden Flowers
              </.link>
            </div>

            <div class="flex items-center justify-end md:gap-4">
              <%!-- Below lg admin sits beside the menu button, and below md sign in moves to the nav drawer --%>
              <.link
                :if={@current_user && @current_user.admin}
                id="admin-shortcut"
                href={~p"/admin"}
                class="group hidden shrink-0 items-center gap-2 lg:flex"
              >
                <.icon class="text-base-content h-5 w-5 group-hover:text-base-content/60" name="hero-squares-2x2" />
                <span class="text-base-content whitespace-nowrap text-sm group-hover:text-base-content/60">Admin</span>
              </.link>

              <.link
                navigate={if @current_user, do: ~p"/account"}
                href={unless @current_user, do: sign_in_href(@current_path)}
                class="group hidden h-10 w-10 shrink-0 items-center justify-center gap-1 md:flex md:h-auto md:w-auto md:gap-2"
              >
                <.icon class="text-base-content h-5 w-5 group-hover:text-base-content/60" name="hero-user-circle" />
                <span class="text-base-content hidden whitespace-nowrap text-sm group-hover:text-base-content/60 md:inline-flex">
                  {if @current_user,
                    do: ~t"Account",
                    else: ~t"Sign In"}
                </span>
              </.link>

              <%!-- Below xl the full language name crowds the logo, so show the short code instead --%>
              <.locale_picker id="locale-picker-header" current_path={@current_path} alternates={@alternates}>
                <span class="group flex h-10 cursor-pointer items-center gap-1 px-1 xl:gap-2 xl:px-0">
                  <.icon name="hero-globe-alt" class="text-base-content h-5 w-5 group-hover:text-base-content/60" />
                  <span
                    class="text-base-content hidden text-sm group-hover:text-base-content/60 sm:inline xl:hidden"
                    aria-hidden="true"
                  >
                    {@current_language_code}
                  </span>
                  <span class="text-base-content sr-only text-sm group-hover:text-base-content/60 xl:not-sr-only">
                    {@current_locale}
                  </span>
                </span>
              </.locale_picker>

              <.cart_count_badge
                count={@order.total_items_in_cart}
                phx-click={JS.exec("phx-show", to: "#cart-drawer")}
              >
                <.icon
                  class="text-base-content h-5 w-5 group-hover:text-base-content/60"
                  name="hero-shopping-bag"
                />
                <%= if @order.total_items_in_cart > 0 do %>
                  <span class="absolute top-0 right-0 lg:hidden" aria-hidden="true">
                    <div class="bg-primary text-primary-content border-base-100 text-[10px] inline-flex h-5 w-5 items-center justify-center rounded-full border-2 font-semibold leading-none">
                      {@order.total_items_in_cart}
                    </div>
                  </span>
                <% end %>
                <span
                  class="text-base-content hidden text-sm group-hover:text-base-content/60 lg:inline-flex"
                  aria-hidden="true"
                >
                  <%= if @order.total_items_in_cart > 0 do %>
                    {~t"Cart"} ({@order.total_items_in_cart})
                  <% else %>
                    {~t"Cart"}
                  <% end %>
                </span>
              </.cart_count_badge>
            </div>
          </div>
        </section>
      </header>
    </div>

    <.flash_group flash={@flash} />

    <main id="main-content" tabindex="-1" class="flex-grow outline-hidden">
      {render_slot(@inner_block)}
    </main>

    <footer>
      <div class="bg-cream relative overflow-hidden border-t border-b">
        <.flower
          name="flower-41"
          class="text-base-content/15 pointer-events-none absolute top-6 right-6 h-20 w-20 md:top-10 md:right-10 md:h-28 md:w-28"
        />
        <div class="container relative py-20 md:py-36">
          <div class="footer-grid">
            <div id="newsletter" class="footer-grid__newsletter space-y-4">
              <.live_component id="newsletter-signup-form" module={EdenflowersWeb.NewsletterSignup} />
            </div>

            <div class="footer-grid__location space-y-2">
              <h3 class="eyebrow text-base-content/70">{~t"Address"}</h3>
              <a
                href={Business.maps_url()}
                target="_blank"
                rel="noopener noreferrer"
                class="link-underline-static-body block space-y-2"
              >
                <p class="footer-line whitespace-nowrap">Minimossen</p>
                <p class="footer-line whitespace-nowrap">{Business.street_address()}</p>
                <p class="footer-line whitespace-nowrap">{Business.postal_town()}</p>
              </a>
            </div>

            <div class="footer-grid__hours space-y-2">
              <h3 class="eyebrow text-base-content/70">
                {~t"Opening hours"}
              </h3>
              <div class="space-y-1">
                <p :for={line <- Business.opening_hours_lines()} class="footer-line whitespace-nowrap">{line}</p>
              </div>
            </div>

            <div class="footer-grid__help space-y-2">
              <h3 class="eyebrow text-base-content/70">{~t"Help"}</h3>
              <ul class="space-y-1">
                <li>
                  <.link
                    navigate={~q"/#{language}/faq"}
                    class="footer-line link-underline-hover pointer-coarse:inline-block pointer-coarse:py-2.5"
                  >
                    {~t"FAQ"}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~q"/#{language}/contact"}
                    class="footer-line link-underline-hover pointer-coarse:inline-block pointer-coarse:py-2.5"
                  >
                    {~t"Contact"}
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~q"/#{language}/about"}
                    class="footer-line link-underline-hover pointer-coarse:inline-block pointer-coarse:py-2.5"
                  >
                    {~t"About"}
                  </.link>
                </li>
              </ul>
            </div>

            <div class="footer-grid__socials space-y-2">
              <h3 class="eyebrow text-base-content/70">{~t"Socials"}</h3>
              <.social_media_links />
            </div>
          </div>
        </div>
      </div>

      <div class="container">
        <div class="flex flex-col items-center gap-3 py-6">
          <.footer_locale_picker current_path={@current_path} alternates={@alternates} current_locale={@current_locale} />

          <span class="text-xs">
            © Eden Flowers {Edenflowers.ShopTime.now() |> Map.get(:year)} • {~t"Business ID:"}
            <a
              class="text-base-content link-underline-hover whitespace-nowrap"
              href="https://tietopalvelu.ytj.fi/yritys/2944459-6"
              target="_blank"
              rel="noopener"
            >
              2944459-6
            </a>
            •
            <a
              class="text-base-content link-underline-hover whitespace-nowrap"
              href="https://github.com/davemccrea/edenflowers_store"
            >
              {~t"Built with "} <span>❤️</span>
            </a>
          </span>
        </div>
      </div>
    </footer>
    """
  end
end

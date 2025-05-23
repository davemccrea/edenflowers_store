defmodule EdenflowersWeb.Router do
  use EdenflowersWeb, :router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EdenflowersWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug EdenflowersWeb.Plugs.InitStore

    plug Cldr.Plug.PutLocale,
      apps: [:cldr, :gettext],
      from: [:session, :accept_language],
      gettext: EdenflowersWeb.Gettext,
      cldr: Edenflowers.Cldr

    plug Cldr.Plug.PutSession, as: :string
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", EdenflowersWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [
        EdenflowersWeb.Hooks.PutLocale,
        EdenflowersWeb.Hooks.PutOrder,
        EdenflowersWeb.Hooks.HandleLineItemChanged
      ] do
      live "/", HomeLive
      live "/courses", CoursesLive
      live "/weddings", WeddingsLive
      live "/condolences", CondolencesLive
      live "/about", AboutLive
      live "/contact", ContactLive
      live "/product/:id", ProductLive
      live "/checkout", CheckoutLive
      live "/order/:id", OrderLive
      live "/account", AccountLive
    end

    get "/checkout/complete/:id", CheckoutCompleteController, :index
    get "/cldr_locale/:cldr_locale", LocaleController, :index

    auth_routes AuthController, Edenflowers.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Using a custom live view which only handles magic link strategy
    sign_in_route(
      live_view: EdenflowersWeb.MagicLinkRequestLive,
      auth_routes_prefix: "/auth",
      on_mount: [
        {EdenflowersWeb.LiveUserAuth, :live_no_user},
        EdenflowersWeb.Hooks.PutLocale
      ]
    )

    magic_sign_in_route(Edenflowers.Accounts.User, :magic_link,
      live_view: EdenflowersWeb.MagicLinkCompleteLive,
      auth_routes_prefix: "/auth",
      on_mount: [
        EdenflowersWeb.Hooks.PutLocale
      ]
    )
  end

  # TODO: auth
  scope "/admin", EdenflowersWeb do
    pipe_through :browser
    oban_dashboard("/oban")
  end

  # Other scopes may use custom stacks.
  # scope "/api", EdenflowersWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:edenflowers, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EdenflowersWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

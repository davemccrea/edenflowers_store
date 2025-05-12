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

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {EdenflowersWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {EdenflowersWeb.LiveUserAuth, :live_no_user}
    end
  end

  scope "/", EdenflowersWeb do
    pipe_through :browser

    live_session :default,
      on_mount: [
        {EdenflowersWeb.Hooks.InitStore, :put_locale},
        {EdenflowersWeb.Hooks.InitStore, :put_order},
        {EdenflowersWeb.Hooks.InitStore, :attach_hooks}
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
    end

    get "/checkout/complete/:id", CheckoutCompleteController, :index
    get "/cldr_locale/:cldr_locale", LocaleController, :index
    auth_routes AuthController, Edenflowers.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{EdenflowersWeb.LiveUserAuth, :live_no_user}],
                  overrides: [EdenflowersWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [EdenflowersWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the confirmation strategy
    confirm_route Edenflowers.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [EdenflowersWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Edenflowers.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [EdenflowersWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
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

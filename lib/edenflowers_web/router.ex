defmodule EdenflowersWeb.Router do
  use EdenflowersWeb, :router
  use AshAuthentication.Phoenix.Router

  import AshAdmin.Router
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EdenflowersWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug EdenflowersWeb.Plugs.InitStore
    plug EdenflowersWeb.Plugs.Maintenance

    plug Localize.Plug.PutLocale,
      from: [:session, :accept_language],
      gettext: EdenflowersWeb.Gettext,
      default: "en-GB"

    plug EdenflowersWeb.Plugs.PutLocaleSession
    plug EdenflowersWeb.Plugs.CaptureReturnTo
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", EdenflowersWeb do
    pipe_through :browser

    ash_authentication_live_session :public,
      on_mount: [
        EdenflowersWeb.Hooks.PutLocale,
        EdenflowersWeb.Hooks.PutCurrentPath,
        EdenflowersWeb.Hooks.PutOrder,
        EdenflowersWeb.Hooks.HandleLineItemChanged
      ] do
      scope "/", Marketing do
        live "/", HomeLive
        live "/maternity", MaternityLive
        live "/courses", CoursesLive
        live "/weddings", WeddingsLive
        live "/condolences", CondolencesLive
        live "/about", AboutLive
        live "/contact", ContactLive
        live "/faq", FaqLive
      end

      scope "/", Store do
        live "/store", StoreLive
        live "/store/:category", StoreLive
        live "/product/:id", ProductLive
      end

      scope "/", Checkout do
        live "/checkout", CheckoutLive
        live "/order/:id", OrderLive
      end

      scope "/", Account do
        live "/account", AccountLive
      end
    end

    get "/checkout/complete/:id", Checkout.CheckoutCompleteController, :index
    get "/locale/:locale", LocaleController, :index

    auth_routes Auth.AuthController, Edenflowers.Accounts.User, path: "/auth"
    sign_out_route Auth.AuthController

    sign_in_route(
      live_view: EdenflowersWeb.Auth.OtpSignInLive,
      auth_routes_prefix: "/auth",
      on_mount: [
        {EdenflowersWeb.Auth.LiveUserAuth, :live_no_user},
        EdenflowersWeb.Hooks.PutLocale,
        EdenflowersWeb.Hooks.PutCurrentPath
      ]
    )
  end

  scope "/admin", EdenflowersWeb do
    pipe_through :browser

    ash_authentication_live_session :admin,
      on_mount: [{EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}] do
      live "/fulfillment-calendar", Admin.FulfillmentCalendarLive
    end
  end

  scope "/admin" do
    pipe_through :browser

    oban_dashboard("/oban", resolver: EdenflowersWeb.ObanResolver)

    ash_admin(
      "/",
      AshAuthentication.Phoenix.LiveSession.opts(on_mount: [{EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}])
    )
  end

  if Application.compile_env(:edenflowers, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EdenflowersWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

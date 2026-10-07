defmodule EdenflowersWeb.Router do
  use EdenflowersWeb, :router
  use AshAuthentication.Phoenix.Router

  import AshAdmin.Router
  import Oban.Web.Router
  use ErrorTracker.Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EdenflowersWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug EdenflowersWeb.Plugs.Maintenance

    plug Localize.Plug.PutLocale,
      from: [:session, :accept_language],
      gettext: EdenflowersWeb.Gettext,
      default: "en-GB"

    plug EdenflowersWeb.Plugs.PutLocaleSession
    plug EdenflowersWeb.Plugs.CaptureReturnTo
    plug :load_from_session
  end

  pipeline :store do
    plug EdenflowersWeb.Plugs.InitStore
  end

  scope "/", EdenflowersWeb do
    pipe_through [:browser, :store]

    ash_authentication_live_session :public,
      on_mount: [
        EdenflowersWeb.Hooks.PutLocale,
        EdenflowersWeb.Hooks.PutCurrentPath,
        EdenflowersWeb.Hooks.PutOrder,
        EdenflowersWeb.Hooks.HandleLineItemChanged
      ] do
      scope "/", Marketing do
        live "/", HomeLive
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

      scope "/", Courses do
        live "/courses", CoursesLive
        live "/courses/bookings/:id", CourseBookingLive
        live "/courses/:id", CourseLive
      end

      scope "/", Checkout do
        live "/checkout", CheckoutLive
        live "/order/:id", OrderLive
        live "/pay/:token", PayLive
      end

      scope "/", Account do
        live "/account", AccountLive
        live "/account/subscriptions/:id/card", SubscriptionCardLive
      end
    end

    get "/checkout/complete/:id", Checkout.CheckoutCompleteController, :index
    get "/order/:id/receipt", Checkout.ReceiptController, :show
    get "/order/:id/pickup.ics", Checkout.PickupCalendarController, :show
  end

  scope "/", EdenflowersWeb do
    pipe_through :browser

    live_session :maintenance do
      live "/back-soon", Marketing.MaintenanceLive
    end

    get "/courses/bookings/:id/receipt", Courses.CourseReceiptController, :show
    get "/locale/:locale", LocaleController, :index

    auth_routes Auth.AuthController, Edenflowers.Accounts.User, path: "/auth"

    sign_out_route(Auth.AuthController, "/sign-out",
      live_view: EdenflowersWeb.Auth.SignOutLive,
      on_mount: [
        {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional},
        EdenflowersWeb.Hooks.PutLocale,
        EdenflowersWeb.Hooks.PutCurrentPath
      ]
    )

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

  scope "/admin" do
    pipe_through :browser

    ash_authentication_live_session :admin,
      on_mount: [
        {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required},
        EdenflowersWeb.Hooks.PutLocale,
        EdenflowersWeb.Hooks.PutCurrentPath
      ] do
      live "/", EdenflowersWeb.Admin.DashboardLive
      live "/orders", EdenflowersWeb.Admin.OrdersLive
      live "/orders/new", EdenflowersWeb.Admin.OrderFormLive
      live "/orders/:id", EdenflowersWeb.Admin.OrderDetailLive
      live "/orders/:id/edit", EdenflowersWeb.Admin.OrderFormLive
      live "/customers", EdenflowersWeb.Admin.CustomersLive
      live "/customers/:id", EdenflowersWeb.Admin.CustomerDetailLive
      live "/subscriptions", EdenflowersWeb.Admin.SubscriptionsLive
      live "/fulfillments", EdenflowersWeb.Admin.FulfillmentCalendarLive
      live "/courses", EdenflowersWeb.Admin.CoursesLive
      live "/courses/new", EdenflowersWeb.Admin.CourseFormLive
      live "/courses/:id", EdenflowersWeb.Admin.CourseFormLive
      live "/products", EdenflowersWeb.Admin.ProductsLive
      live "/products/new", EdenflowersWeb.Admin.ProductFormLive
      live "/products/:id", EdenflowersWeb.Admin.ProductFormLive
      live "/promotions", EdenflowersWeb.Admin.PromotionsLive
      live "/promotions/new", EdenflowersWeb.Admin.PromotionFormLive
      live "/promotions/:id", EdenflowersWeb.Admin.PromotionFormLive
      live "/expenses", EdenflowersWeb.Admin.ExpensesLive
      live "/expenses/:id", EdenflowersWeb.Admin.ExpenseDetailLive
      live "/account", EdenflowersWeb.Admin.AccountLive
      live "/chat", EdenflowersWeb.Admin.ChatLive
      live "/chat/:conversation_id", EdenflowersWeb.Admin.ChatLive
    end

    get "/account/avatar", EdenflowersWeb.Admin.AvatarController, :show

    oban_dashboard("/oban", resolver: EdenflowersWeb.ObanResolver)

    error_tracker_dashboard("/errors",
      on_mount: [
        {EdenflowersWeb.Auth.LiveUserAuth, :current_user},
        {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}
      ]
    )

    ash_admin(
      "/ash",
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

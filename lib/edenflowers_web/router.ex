defmodule EdenflowersWeb.Router do
  @moduledoc """
  Routes public, checkout, account, and admin requests through their
  authentication and locale pipelines. Stripe and Papra webhooks are plugs in
  `EdenflowersWeb.Endpoint`, not routes here.
  """

  use EdenflowersWeb, :router
  use AshAuthentication.Phoenix.Router
  use ErrorTracker.Web, :router
  use Localize.Routes, gettext: EdenflowersWeb.Gettext, helpers: false

  import AshAdmin.Router
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug EdenflowersWeb.Plugs.PutClientIp
    plug :put_root_layout, html: {EdenflowersWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    plug Localize.Plug.PutLocale,
      from: [:route, :session, :accept_language],
      gettext: EdenflowersWeb.Gettext,
      default: Edenflowers.Locales.default()

    plug EdenflowersWeb.Plugs.PutLocaleSession
    plug EdenflowersWeb.Plugs.CaptureReturnTo
    plug :load_from_session
    plug EdenflowersWeb.Plugs.Maintenance
  end

  pipeline :admin_locale do
    plug EdenflowersWeb.Plugs.PutAdminLocale
  end

  pipeline :browser_json do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :load_from_session
  end

  pipeline :store do
    plug EdenflowersWeb.Plugs.InitStore
    plug EdenflowersWeb.Plugs.ApplyLinkPromotion
    plug EdenflowersWeb.Plugs.RedirectOldLinks
  end

  scope "/", EdenflowersWeb do
    pipe_through [:browser, :store]

    ash_authentication_live_session :public,
      on_mount: [
        EdenflowersWeb.Hooks.Maintenance,
        EdenflowersWeb.Hooks.TrackPresence,
        EdenflowersWeb.Hooks.PutLocale,
        EdenflowersWeb.Hooks.PutCurrentPath,
        EdenflowersWeb.Hooks.PutOrder,
        EdenflowersWeb.Hooks.PutNoticeBar,
        EdenflowersWeb.Hooks.PutClientIp,
        EdenflowersWeb.Hooks.HandleLineItemChanged
      ] do
      localize do
        live "/#{language}", Marketing.HomeLive
        live "/#{language}/weddings", Marketing.WeddingsLive
        live "/#{language}/condolences", Marketing.CondolencesLive
        live "/#{language}/pass-it-on", Marketing.PassItOnLive
        live "/#{language}/about", Marketing.AboutLive
        live "/#{language}/contact", Marketing.ContactLive
        live "/#{language}/faq", Marketing.FaqLive
        live "/#{language}/terms", Marketing.TermsLive
        live "/#{language}/privacy", Marketing.PrivacyLive
        live "/#{language}/store", Store.StoreLive
        live "/#{language}/store/:category", Store.StoreLive
        live "/#{language}/product/:slug", Store.ProductLive
        live "/#{language}/gift-voucher", Store.GiftVoucherLive
        live "/#{language}/courses", Courses.CoursesLive
        live "/#{language}/courses/:slug", Courses.CourseLive
      end

      scope "/", Courses do
        live "/courses/bookings/:id", CourseBookingLive
      end

      scope "/", Checkout do
        live "/checkout", CheckoutLive
        live "/order/:id", OrderLive
      end

      scope "/", Account do
        live "/account", AccountLive
        live "/account/subscriptions/:id/card", SubscriptionCardLive
      end
    end

    # Payment links stay open during maintenance, so they sit outside :public and
    # its maintenance hook. Leaving one is a full page load through Plugs.Maintenance.
    ash_authentication_live_session :payment_link,
      on_mount: [
        EdenflowersWeb.Hooks.TrackPresence,
        EdenflowersWeb.Hooks.PutLocale,
        EdenflowersWeb.Hooks.PutCurrentPath,
        EdenflowersWeb.Hooks.PutOrder,
        EdenflowersWeb.Hooks.HandleLineItemChanged
      ] do
      live "/pay/courses/:token", Courses.CoursePayLive
      live "/pay/orders/:token", Checkout.PayLive
    end

    get "/checkout/complete/:id", Checkout.CheckoutCompleteController, :index
    get "/order/:id/receipt", Checkout.ReceiptController, :show
    get "/order/:id/pickup.ics", Checkout.PickupCalendarController, :show

    # Links without a language, for sharing and print. Only pages someone links to get one.
    get "/", Marketing.LocalizedRedirectController, :show
    get "/product/:slug", Marketing.LocalizedRedirectController, :product
    get "/courses", Marketing.LocalizedRedirectController, :courses
    get "/courses/:slug", Marketing.LocalizedRedirectController, :course
    get "/weddings", Marketing.LocalizedRedirectController, :weddings
    get "/gift-voucher", Marketing.LocalizedRedirectController, :gift_voucher
    # Printed on the bilingual pass-it-on cards, so it can never change.
    get "/pass-it-on", Marketing.LocalizedRedirectController, :pass_it_on
  end

  scope "/", EdenflowersWeb do
    get "/sitemap.xml", Marketing.SitemapController, :index
    get "/health", HealthController, :show
    get "/pay/:token", PaymentLinkRedirectController, :order
    get "/courses/pay/:token", PaymentLinkRedirectController, :course
    get "/valkommen", Marketing.LegacyRedirectController, :swedish
    get "/tervetuloa", Marketing.LegacyRedirectController, :finnish
    get "/sv/privacy", Marketing.LegacyRedirectController, :swedish_privacy
    get "/fi/privacy", Marketing.LegacyRedirectController, :finnish_privacy
  end

  scope "/", EdenflowersWeb do
    pipe_through :browser

    live_session :maintenance do
      live "/back-soon", Marketing.MaintenanceLive
    end

    get "/courses/bookings/:id/receipt", Courses.CourseReceiptController, :show
    get "/locale/:locale", LocaleController, :index
    get "/admin-locale/:locale", LocaleController, :admin

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

  scope "/", EdenflowersWeb do
    pipe_through :browser_json

    resources "/review-notes", Review.NoteController, only: [:index, :create, :update, :delete]
    post "/review-notes/strings", Review.NoteController, :strings
  end

  scope "/admin", EdenflowersWeb.Admin do
    pipe_through [:browser, :admin_locale]

    ash_authentication_live_session :admin,
      on_mount: [
        {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required},
        {EdenflowersWeb.Hooks.PutLocale, :admin},
        EdenflowersWeb.Hooks.PutCurrentPath,
        EdenflowersWeb.Hooks.HandleAdminSearch
      ] do
      live "/", OverviewLive
      live "/orders", OrdersLive
      live "/orders/new", OrderFormLive
      live "/orders/new-gift-voucher", GiftVoucherSaleLive
      live "/orders/:id", OrderDetailLive
      live "/orders/:id/edit", OrderFormLive
      live "/customers", CustomersLive
      live "/customers/:id", CustomerDetailLive
      live "/subscriptions", SubscriptionsLive
      live "/subscriptions/:id", SubscriptionDetailLive
      live "/fulfillments", FulfillmentsLive, :index
      live "/fulfillments/:id", FulfillmentsLive, :edit
      live "/courses", CoursesLive
      live "/courses/new", CourseFormLive
      live "/courses/:id", CourseDetailLive
      live "/courses/:id/edit", CourseFormLive
      live "/courses/:id/bookings/new", CourseBookingFormLive
      live "/products", ProductsLive
      live "/products/categories", CategoriesLive
      live "/products/new", ProductFormLive
      live "/products/:id", ProductFormLive
      live "/promotions", PromotionsLive
      live "/promotions/new", PromotionFormLive
      live "/promotions/:id", PromotionFormLive
      live "/invoices", InvoicesLive
      live "/invoices/new", InvoiceLive, :new
      live "/invoices/:id", InvoiceLive, :show
      live "/expenses", ExpensesLive
      live "/expenses/:id", ExpenseDetailLive
      live "/account", AccountLive
      live "/search", SearchLive
      live "/links", LinksLive
    end

    get "/account/avatar", AvatarController, :show
    get "/reports", ReportController, :show
    get "/bank/callback", BankController, :callback
    get "/invoices/:id/pdf", InvoiceController, :show
    get "/credit-notes/:id", InvoiceController, :credit_note
  end

  # Library dashboards name their own modules, so this scope has no alias.
  scope "/admin" do
    pipe_through [:browser, :admin_locale]

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

defmodule EdenflowersWeb do
  @moduledoc """
  Shared imports and setup for the Phoenix web layer.

  Web modules select their role with `use`, for example:

      use EdenflowersWeb, :controller
      use EdenflowersWeb, :live_view
      use EdenflowersWeb, :html

  The role macros add localized routes, Gettext sigils, layouts, and core
  components as appropriate. Keep the quoted definitions here limited to
  shared setup; page behavior belongs in the individual modules.
  """

  def static_paths,
    do:
      ~w(assets fonts images favicon.ico favicon.svg favicon-96x96.png apple-touch-icon.png site.webmanifest admin.webmanifest admin-sw.js web-app-manifest-192x192.png web-app-manifest-512x512.png robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn

      use GettextSigils,
        backend: EdenflowersWeb.Gettext

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use GettextSigils, backend: EdenflowersWeb.Gettext

      import Phoenix.HTML
      import EdenflowersWeb.CoreComponents

      alias EdenflowersWeb.Layouts
      alias Phoenix.LiveView.JS

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Localize.VerifiedRoutes,
        endpoint: EdenflowersWeb.Endpoint,
        router: EdenflowersWeb.Router,
        gettext: EdenflowersWeb.Gettext,
        statics: EdenflowersWeb.static_paths()

      import EdenflowersWeb.LocalizedPaths, only: [alternates: 1]
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

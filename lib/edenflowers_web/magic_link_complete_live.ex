defmodule EdenflowersWeb.MagicLinkCompleteLive do
  use EdenflowersWeb, :live_view

  import AshAuthentication.Phoenix.Components.Helpers, only: [auth_path: 5]

  alias AshAuthentication.Info
  alias Edenflowers.Accounts.User

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :token, params["token"] || params["magic_link"])}
  end

  def mount(_params, session, socket) do
    strategy = Info.strategy!(User, :magic_link)
    domain = Info.authentication_domain!(strategy.resource)
    subject_name = Info.authentication_subject_name!(strategy.resource)
    current_tenant = session["tenant"]

    form =
      strategy.resource
      |> AshPhoenix.Form.for_action(strategy.sign_in_action_name,
        transform_errors: fn _source, error ->
          error
        end,
        domain: domain,
        tenant: current_tenant,
        as: to_string(subject_name),
        id: "magic-link-complete",
        context: %{strategy: strategy, private: %{ash_authentication?: true}}
      )

    {:ok,
     socket
     |> assign(form: form)
     |> assign(trigger_action: false)
     |> assign(strategy: strategy)
     |> assign(subject_name: subject_name)
     |> assign(auth_routes_prefix: "/auth")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <section class="bg-base-100 flex w-full max-w-lg flex-col space-y-8 p-8 shadow-lg">
        <h2 class="text-center text-lg font-bold">
          {gettext("Complete sign in")}
        </h2>

        <.form
          class="flex flex-col"
          for={@form}
          phx-submit="submit"
          method="POST"
          phx-trigger-action={@trigger_action}
          action={
            auth_path(
              @socket,
              @subject_name,
              @auth_routes_prefix,
              @strategy,
              :sign_in
            )
          }
        >
          <input type="hidden" name="token" value={@token} />

          <button type="submit" class="btn btn-primary btn-lg">
            {gettext("Sign in")}
            <.icon name="hero-arrow-right" />
          </button>
        </.form>
      </section>
    </Layouts.auth>
    """
  end

  def handle_event("submit", params, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    socket =
      if form.valid? do
        socket
        |> assign(:form, form)
        |> assign(:trigger_action, true)
      else
        error_toast =
          EdenflowersWeb.LiveToast.new(
            :warning,
            gettext("Error signing in. Please try again later.")
          )

        socket
        |> push_event("toast:show", error_toast)
        |> assign(form: form)
      end

    {:noreply, socket}
  end
end

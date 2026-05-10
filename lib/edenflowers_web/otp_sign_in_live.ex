defmodule EdenflowersWeb.OtpSignInLive do
  use EdenflowersWeb, :live_view

  import AshAuthentication.Phoenix.Components.Helpers, only: [auth_path: 5]

  alias AshAuthentication.Info
  alias Edenflowers.Accounts.User

  # Seconds the user must wait between resend attempts. Server-side
  # AshRateLimiter on :request_otp is the safety net (5 / 15 min); this is
  # purely a UX brake so users don't burn through their quota.
  @resend_cooldown_seconds 30

  def mount(_params, session, socket) do
    strategy = Info.strategy!(User, :otp)

    socket =
      socket
      |> assign(strategy: strategy)
      |> assign(current_tenant: session["tenant"])
      |> assign(context: session["context"] || %{})
      |> assign(email: nil)
      |> assign(trigger_action: false)
      |> assign(resend_remaining: 0)
      |> assign(subject_name: Info.authentication_subject_name!(strategy.resource))
      |> assign(auth_routes_prefix: "/auth")
      |> assign_request_form()
      |> assign_sign_in_form()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_path={@current_path}>
      <section class="bg-base-100 flex w-full max-w-lg flex-col space-y-4 p-8 shadow-lg">
        <h2 class="text-center text-lg font-bold">
          {~t"Sign in to your account"}
        </h2>

        <%= if @email do %>
          <p class="text-center text-sm">
            {~t"🥳 A sign-in code was sent to #{@email}."}
          </p>

          <.form
            class="flex w-full flex-col space-y-4"
            for={@sign_in_form}
            phx-submit="verify"
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
            <%!-- Mirrors the email so the form-trigger handoff carries it through. --%>
            <input type="hidden" name="user[email]" value={@email} />

            <.input
              autofocus
              field={@sign_in_form[:otp]}
              label={~t"Sign-in code"}
              autocomplete="one-time-code"
              inputmode="text"
              maxlength="6"
              pattern="[A-Za-z0-9]{6}"
              spellcheck="false"
              autocapitalize="characters"
            />

            <.button type="submit" variant="primary" size="lg">
              {~t"Sign in"}
              <.icon name="hero-arrow-right" />
            </.button>
          </.form>

          <div class="flex flex-col items-center gap-2 text-center text-sm">
            <%= if @resend_remaining > 0 do %>
              <span class="text-base-content/50">
                {~t"Resend code in"} {@resend_remaining}s
              </span>
            <% else %>
              <button type="button" phx-click="resend" class="link-underline-hover-nav">
                {~t"Resend code"}
              </button>
            <% end %>
            <button type="button" phx-click="reset" class="link-underline-hover-nav">
              {~t"Use a different email"}
            </button>
          </div>
        <% else %>
          <.form
            class="flex w-full flex-col space-y-4"
            for={@request_form}
            phx-change="change"
            phx-submit="request"
            method="POST"
          >
            <.input
              autofocus
              field={@request_form[:email]}
              label={~t"Email"}
              placeholder={~t"info@edenflowers.fi"}
              type="email"
              autocomplete="email"
            />

            <.button type="submit" variant="primary" size="lg">
              {~t"Send sign-in code"}
              <.icon name="hero-arrow-right" />
            </.button>
          </.form>
        <% end %>
      </section>
    </Layouts.auth>
    """
  end

  def handle_event("change", %{"user" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.request_form, params)
    {:noreply, assign(socket, request_form: form)}
  end

  def handle_event("request", %{"user" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.request_form, params: params) do
      {:ok, _} ->
        {:noreply, socket |> assign(email: params["email"]) |> start_resend_cooldown()}

      :ok ->
        {:noreply, socket |> assign(email: params["email"]) |> start_resend_cooldown()}

      {:error, form} ->
        {:noreply, socket |> assign(request_form: form) |> request_error_toast()}
    end
  end

  def handle_event("verify", params, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.sign_in_form, params["user"] || %{})

    socket =
      if form.source.valid? do
        socket
        |> assign(:sign_in_form, form)
        |> assign(:trigger_action, true)
      else
        socket
        |> put_flash(:warning, ~t"That doesn't look like a valid code. Please check and try again.")
        |> assign(sign_in_form: form)
      end

    {:noreply, socket}
  end

  def handle_event("resend", _params, %{assigns: %{email: email}} = socket) when is_binary(email) do
    if socket.assigns.resend_remaining > 0 do
      {:noreply, socket}
    else
      params = %{"email" => email}

      case AshPhoenix.Form.submit(socket.assigns.request_form, params: params) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, ~t"We've sent you a new code.") |> start_resend_cooldown()}

        :ok ->
          {:noreply, socket |> put_flash(:info, ~t"We've sent you a new code.") |> start_resend_cooldown()}

        {:error, form} ->
          {:noreply, socket |> assign(request_form: form) |> request_error_toast()}
      end
    end
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> assign(email: nil)
     |> assign(trigger_action: false)
     |> assign(resend_remaining: 0)
     |> assign_request_form()
     |> assign_sign_in_form()}
  end

  def handle_info(:resend_tick, socket) do
    remaining = socket.assigns.resend_remaining - 1

    if remaining > 0 do
      Process.send_after(self(), :resend_tick, 1_000)
      {:noreply, assign(socket, resend_remaining: remaining)}
    else
      {:noreply, assign(socket, resend_remaining: 0)}
    end
  end

  defp start_resend_cooldown(socket) do
    Process.send_after(self(), :resend_tick, 1_000)
    assign(socket, resend_remaining: @resend_cooldown_seconds)
  end

  defp assign_request_form(%{assigns: %{strategy: strategy, current_tenant: current_tenant, context: context}} = socket) do
    domain = Info.authentication_domain!(strategy.resource)
    subject_name = Info.authentication_subject_name!(strategy.resource)

    form =
      strategy.resource
      |> AshPhoenix.Form.for_action(strategy.request_action_name,
        domain: domain,
        as: to_string(subject_name),
        id: "otp-request",
        tenant: current_tenant,
        transform_errors: fn _source, error -> error end,
        context:
          Ash.Helpers.deep_merge_maps(context, %{
            strategy: strategy,
            private: %{ash_authentication?: true}
          })
      )
      |> to_form()

    assign(socket, request_form: form)
  end

  defp assign_sign_in_form(%{assigns: %{strategy: strategy, current_tenant: current_tenant, context: context}} = socket) do
    domain = Info.authentication_domain!(strategy.resource)
    subject_name = Info.authentication_subject_name!(strategy.resource)

    form =
      strategy.resource
      |> AshPhoenix.Form.for_action(strategy.sign_in_action_name,
        domain: domain,
        as: to_string(subject_name),
        id: "otp-sign-in",
        tenant: current_tenant,
        transform_errors: fn _source, error -> error end,
        context:
          Ash.Helpers.deep_merge_maps(context, %{
            strategy: strategy,
            private: %{ash_authentication?: true}
          })
      )
      |> to_form()

    assign(socket, sign_in_form: form)
  end

  defp request_error_toast(socket) do
    put_flash(socket, :warning, ~t"We couldn't send your sign-in code. Please try again in a moment.")
  end
end
